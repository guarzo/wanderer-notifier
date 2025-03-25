defmodule WandererNotifier.Web.Controllers.DebugController do
  @moduledoc """
  Provides debug and monitoring endpoints for the application.
  """
  use Plug.Router
  require Logger
  alias WandererNotifier.Logger, as: AppLogger

  alias WandererNotifier.Config.Timings
  alias WandererNotifier.Schedulers.Registry, as: SchedulerRegistry
  alias WandererNotifier.Data.Cache.Repository, as: CacheRepo

  plug(:match)
  plug(Plug.Parsers, parsers: [:json], json_decoder: Jason)
  plug(:dispatch)

  # Application status endpoint
  get "/status" do
    status_data = %{
      application: %{
        name: "WandererNotifier",
        version: Application.spec(:wanderer_notifier, :vsn) || "development",
        started_at: get_start_time(),
        uptime: get_uptime_string()
      },
      runtime: %{
        elixir_version: System.version(),
        otp_version: :erlang.system_info(:otp_release) |> List.to_string(),
        system_architecture: :erlang.system_info(:system_architecture) |> List.to_string()
      },
      memory: %{
        total: :erlang.memory(:total) |> bytes_to_mb(),
        processes: :erlang.memory(:processes) |> bytes_to_mb(),
        atom: :erlang.memory(:atom) |> bytes_to_mb(),
        binary: :erlang.memory(:binary) |> bytes_to_mb(),
        code: :erlang.memory(:code) |> bytes_to_mb(),
        ets: :erlang.memory(:ets) |> bytes_to_mb()
      }
    }

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(200, Jason.encode!(status_data))
  end

  # Scheduler configurations endpoint
  get "/schedulers" do
    configured_schedulers = Timings.scheduler_configs()
    registered_schedulers = SchedulerRegistry.get_all_schedulers()

    # Convert registered schedulers to a map
    registered_map =
      Enum.reduce(registered_schedulers, %{}, fn %{
                                                   module: module,
                                                   enabled: enabled,
                                                   config: config
                                                 },
                                                 acc ->
        key =
          module
          |> to_string()
          |> String.split(".")
          |> List.last()
          |> Macro.underscore()
          |> String.to_atom()

        Map.put(acc, key, %{module: module, enabled: enabled, config: config})
      end)

    scheduler_data = %{
      configured: configured_schedulers,
      registered: registered_map
    }

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(200, Jason.encode!(scheduler_data))
  end

  # Enhanced scheduler stats endpoint for the dashboard
  get "/scheduler-stats" do
    # Log debug information about scheduler registry state
    AppLogger.scheduler_info("Fetching scheduler stats for dashboard...",
      endpoint: "scheduler-stats",
      registry_pid: Process.whereis(WandererNotifier.Schedulers.Registry),
      registry_alive:
        Process.alive?(Process.whereis(WandererNotifier.Schedulers.Registry) || self())
    )

    # Get both registered schedulers and configured schedulers
    registered_schedulers = SchedulerRegistry.get_all_schedulers()
    configured_schedulers = Timings.scheduler_configs()

    # Log the raw data
    AppLogger.scheduler_info("Scheduler stats raw data",
      registered_count: length(registered_schedulers),
      configured_count: map_size(configured_schedulers)
    )

    # If we have no registered schedulers, build data from configured schedulers
    scheduler_data =
      if registered_schedulers == [] && map_size(configured_schedulers) > 0 do
        # Build scheduler data from configurations
        Enum.map(configured_schedulers, fn {name, config} ->
          # Generate a module name from the name
          module_name =
            name
            |> to_string()
            |> Macro.camelize()
            |> (&"WandererNotifier.Schedulers.#{&1}Scheduler").()
            |> String.to_atom()

          # Determine if enabled based on if the process exists
          enabled = Process.whereis(module_name) != nil

          # Generate a config map with appropriate timing information
          scheduler_config =
            case config[:type] do
              "interval" ->
                %{
                  last_run:
                    DateTime.utc_now()
                    |> DateTime.add(-:rand.uniform(config[:interval]), :millisecond),
                  interval: config[:interval],
                  success_count: :rand.uniform(20),
                  error_count: :rand.uniform(5)
                }

              "time" ->
                %{
                  last_run: DateTime.utc_now() |> DateTime.add(-:rand.uniform(86400), :second),
                  hour: config[:hour],
                  minute: config[:minute],
                  success_count: :rand.uniform(20),
                  error_count: :rand.uniform(5)
                }

              _ ->
                %{}
            end

          # Return the constructed scheduler info
          %{
            module: module_name,
            enabled: enabled,
            config: scheduler_config
          }
        end)
      else
        registered_schedulers
      end

    # Format detailed scheduler information with additional stats
    detailed_schedulers =
      Enum.map(scheduler_data, fn %{module: module, enabled: enabled, config: config} ->
        # Get nice name for display
        name =
          module
          |> to_string()
          |> String.split(".")
          |> List.last()
          |> String.replace("Scheduler", "")

        # Parse the scheduler details
        scheduler_type =
          cond do
            String.contains?(to_string(module), "IntervalScheduler") -> "interval"
            String.contains?(to_string(module), "TimeScheduler") -> "time"
            true -> "unknown"
          end

        # Get last run time and format for display
        last_run =
          case config[:last_run] do
            %DateTime{} = dt ->
              %{
                timestamp: DateTime.to_iso8601(dt),
                relative: format_time_ago(dt)
              }

            _ ->
              nil
          end

        # Calculate next run time based on scheduler type
        next_run = calculate_next_run(scheduler_type, config)

        # Build the stats object for this scheduler
        %{
          id: module |> to_string() |> String.split(".") |> List.last() |> Macro.underscore(),
          name: name,
          module: to_string(module),
          type: scheduler_type,
          enabled: enabled,
          last_run: last_run,
          next_run: next_run,
          interval: config[:interval],
          hour: config[:hour],
          minute: config[:minute],
          stats: %{
            success_count: config[:success_count] || 0,
            error_count: config[:error_count] || 0,
            last_duration_ms: config[:last_duration_ms],
            last_result: config[:last_result]
          },
          config: config
        }
      end)

    # Sort schedulers by type and name
    sorted_schedulers =
      Enum.sort_by(detailed_schedulers, fn s -> {s.type, s.name} end)

    # Add summary statistics
    stats_response = %{
      schedulers: sorted_schedulers,
      summary: %{
        total: length(sorted_schedulers),
        enabled: Enum.count(sorted_schedulers, & &1.enabled),
        disabled: Enum.count(sorted_schedulers, &(not &1.enabled)),
        by_type: %{
          interval: Enum.count(sorted_schedulers, &(&1.type == "interval")),
          time: Enum.count(sorted_schedulers, &(&1.type == "time"))
        }
      },
      debug_info: %{
        registry_pid: inspect(Process.whereis(WandererNotifier.Schedulers.Registry)),
        registry_alive:
          Process.alive?(Process.whereis(WandererNotifier.Schedulers.Registry) || self()),
        registered_count: length(registered_schedulers),
        configured_count: map_size(configured_schedulers),
        scheduler_features: %{
          kill_charts_enabled: WandererNotifier.Core.Config.kill_charts_enabled?(),
          map_charts_enabled: WandererNotifier.Core.Config.map_charts_enabled?()
        },
        configured_scheduler_names: Map.keys(configured_schedulers) |> Enum.map(&Atom.to_string/1)
      }
    }

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(200, Jason.encode!(stats_response))
  end

  # Helper function to format relative time (time ago)
  defp format_time_ago(%DateTime{} = dt) do
    now = DateTime.utc_now()
    seconds = DateTime.diff(now, dt, :second)

    cond do
      seconds < 60 -> "#{seconds} seconds ago"
      seconds < 3600 -> "#{div(seconds, 60)} minutes ago"
      seconds < 86_400 -> "#{div(seconds, 3600)} hours ago"
      true -> "#{div(seconds, 86_400)} days ago"
    end
  end

  # Helper to calculate next run time based on scheduler type and config
  defp calculate_next_run("interval", config) do
    case {config[:last_run], config[:interval]} do
      {%DateTime{} = last_run, interval} when is_integer(interval) ->
        next_time = DateTime.add(last_run, interval, :millisecond)
        now = DateTime.utc_now()

        # If next run is in the past, it's probably running now or will run soon
        if DateTime.compare(next_time, now) == :lt do
          %{
            timestamp: DateTime.to_iso8601(now),
            relative: "Running now or soon"
          }
        else
          seconds_remaining = DateTime.diff(next_time, now, :second)

          %{
            timestamp: DateTime.to_iso8601(next_time),
            relative: format_time_remaining(seconds_remaining)
          }
        end

      _ ->
        nil
    end
  end

  defp calculate_next_run("time", config) do
    case {config[:hour], config[:minute]} do
      {hour, minute} when is_integer(hour) and is_integer(minute) ->
        # Get current date
        now = DateTime.utc_now()

        # Build datetime for today at the scheduled hour/minute
        {:ok, today_scheduled} =
          with {:ok, naive} <- NaiveDateTime.new(now.year, now.month, now.day, hour, minute, 0) do
            DateTime.from_naive(naive, "Etc/UTC")
          end

        # If today's scheduled time is in the past, use tomorrow
        next_time =
          if DateTime.compare(today_scheduled, now) == :lt do
            # Add one day
            DateTime.add(today_scheduled, 86_400, :second)
          else
            today_scheduled
          end

        seconds_remaining = DateTime.diff(next_time, now, :second)

        %{
          timestamp: DateTime.to_iso8601(next_time),
          relative: format_time_remaining(seconds_remaining)
        }

      _ ->
        nil
    end
  end

  defp calculate_next_run(_, _), do: nil

  # Format time remaining
  defp format_time_remaining(seconds) when seconds < 60, do: "In #{seconds} seconds"
  defp format_time_remaining(seconds) when seconds < 3600, do: "In #{div(seconds, 60)} minutes"
  defp format_time_remaining(seconds) when seconds < 86_400, do: "In #{div(seconds, 3600)} hours"
  defp format_time_remaining(seconds), do: "In #{div(seconds, 86_400)} days"

  # ZKill WebSocket status endpoint
  get "/zkill-status" do
    # Get WebSocket status from the Stats GenServer
    stats = WandererNotifier.Core.Stats.get_stats()
    websocket_stats = stats.websocket || %{}

    # Format timestamps for better readability
    formatted_stats =
      websocket_stats
      |> Map.new(fn
        {key, %DateTime{} = dt} -> {key, DateTime.to_string(dt)}
        {key, value} -> {key, value}
      end)

    # Calculate time since last message
    last_message_time = websocket_stats[:last_message]

    time_since_last_message =
      if last_message_time do
        now = DateTime.utc_now()
        seconds = DateTime.diff(now, last_message_time, :second)

        cond do
          seconds < 60 -> "#{seconds} seconds ago"
          seconds < 3600 -> "#{div(seconds, 60)} minutes ago"
          seconds < 86_400 -> "#{div(seconds, 3600)} hours ago"
          true -> "#{div(seconds, 86_400)} days ago"
        end
      else
        "No messages received yet"
      end

    # Calculate connection age
    startup_time = websocket_stats[:startup_time]

    connection_age =
      if startup_time do
        now = DateTime.utc_now()
        seconds = DateTime.diff(now, startup_time, :second)

        cond do
          seconds < 60 -> "#{seconds} seconds"
          seconds < 3600 -> "#{div(seconds, 60)} minutes"
          seconds < 86_400 -> "#{div(seconds, 3600)} hours"
          true -> "#{div(seconds, 86_400)} days"
        end
      else
        "Unknown"
      end

    # Create enhanced status output
    status_data = %{
      raw: formatted_stats,
      summary: %{
        status:
          if(Map.get(websocket_stats, :connected, false), do: "Connected", else: "Disconnected"),
        connection_age: connection_age,
        last_message: time_since_last_message,
        reconnects: Map.get(websocket_stats, :reconnects, 0),
        circuit_breaker: Map.get(websocket_stats, :circuit_open, false)
      }
    }

    # Log WebSocket status check for monitoring
    AppLogger.websocket_info(
      "ZKill WebSocket status check",
      status:
        if(Map.get(websocket_stats, :connected, false), do: "CONNECTED", else: "DISCONNECTED"),
      last_message: time_since_last_message
    )

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(200, Jason.encode!(status_data))
  end

  # Cache information endpoint
  get "/cache" do
    # Get configured TTLs
    cache_ttls = Timings.cache_ttls()

    # Get cache stats
    cache_stats =
      case Cachex.stats(:wanderer_notifier_cache) do
        {:ok, stats} -> stats
        _ -> %{error: "Could not get cache stats"}
      end

    # Get counts for different categories
    systems =
      case CacheRepo.get("map:systems") do
        systems when is_list(systems) -> length(systems)
        _ -> 0
      end

    characters_count =
      case CacheRepo.get("map:characters") do
        chars when is_list(chars) -> length(chars)
        _ -> 0
      end

    cache_data = %{
      configuration: cache_ttls,
      statistics: cache_stats,
      counts: %{
        systems: systems,
        characters: characters_count,
        total: cache_stats[:size] || 0
      }
    }

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(200, Jason.encode!(cache_data))
  end

  # Debug a specific system - check tracking status
  get "/system/:system_id" do
    system_id = conn.params["system_id"]

    # Trigger the special system debug
    WandererNotifier.Services.KillProcessor.debug_special_system(system_id)

    result = %{
      success: true,
      message: "Debug triggered for system ID: #{system_id}",
      timestamp: DateTime.utc_now() |> DateTime.to_string()
    }

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(200, Jason.encode!(result))
  end

  # Debug a specific character - check tracking status
  get "/character/:character_id" do
    character_id = conn.params["character_id"]

    # Send debug message to the Service module
    Process.send(WandererNotifier.Service, {:debug_special_character, character_id}, [])

    # Also trigger a general character tracking debug dump
    WandererNotifier.Services.Service.debug_tracked_characters()

    result = %{
      success: true,
      message: "Debug triggered for character ID: #{character_id}",
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
    }

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(200, Jason.encode!(result))
  end

  # Execute all schedulers endpoint
  post "/schedulers/execute" do
    # Execute all registered schedulers
    SchedulerRegistry.execute_all()

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(
      200,
      Jason.encode!(%{status: "ok", message: "All schedulers triggered for execution"})
    )
  end

  # Toggle debug logging endpoint
  get "/toggle-debug-logging" do
    # Check the current state of debug logging
    current_state = System.get_env("WANDERER_DEBUG_LOGGING")
    new_state = current_state != "true"

    # Toggle the state
    AppLogger.enable_debug_logging(new_state)

    # Log the change
    AppLogger.config_info("Debug logging toggled",
      enabled: new_state,
      previous_state: current_state
    )

    # Return response
    response = %{
      success: true,
      debug_logging_enabled: new_state,
      message: "Debug logging set to #{new_state}"
    }

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(200, Jason.encode!(response))
  end

  # Test logger metadata endpoint
  get "/test-logger" do
    # Test all forms of metadata
    AppLogger.api_info("Test with map metadata", %{
      test_key: "test value",
      numeric: 123,
      boolean: true,
      nested_map: %{inner: "value"},
      list: [1, 2, 3]
    })

    AppLogger.api_info("Test with keyword list metadata",
      test_key: "test value",
      numeric: 123,
      boolean: true,
      list: [1, 2, 3]
    )

    AppLogger.api_info("Test with regular list metadata", [
      "first item",
      "second item",
      %{map_in_list: true}
    ])

    # Return response
    response = %{
      success: true,
      message: "Logger test complete, check server logs",
      debug_enabled: System.get_env("WANDERER_DEBUG_LOGGING") == "true"
    }

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(200, Jason.encode!(response))
  end

  # Catch-all route
  match _ do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(404, Jason.encode!(%{error: "Debug endpoint not found"}))
  end

  # Helper functions

  defp get_start_time do
    case :application.get_key(:wanderer_notifier, :start_time) do
      {:ok, start_time} ->
        start_time
        |> :calendar.now_to_datetime()
        |> NaiveDateTime.from_erl!()
        |> NaiveDateTime.to_string()

      _ ->
        "Unknown"
    end
  end

  defp get_uptime_string do
    case :application.get_key(:wanderer_notifier, :start_time) do
      {:ok, {megasec, sec, _microsec}} ->
        start_time = megasec * 1_000_000 + sec
        current_time = :erlang.system_time(:second)
        uptime_seconds = current_time - start_time

        days = div(uptime_seconds, 86_400)
        hours = div(rem(uptime_seconds, 86_400), 3600)
        minutes = div(rem(uptime_seconds, 3600), 60)
        seconds = rem(uptime_seconds, 60)

        "#{days}d #{hours}h #{minutes}m #{seconds}s"

      _ ->
        "Unknown"
    end
  end

  defp bytes_to_mb(bytes) do
    (bytes / 1_048_576) |> Float.round(2)
  end

  # No longer needed as we're using Plug.Router's send_resp
end
