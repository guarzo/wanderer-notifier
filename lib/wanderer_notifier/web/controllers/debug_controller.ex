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
