defmodule WandererNotifier.Web.Controllers.DebugController do
  @moduledoc """
  Controller for debug endpoints.
  Provides debugging information and tools.
  """

  use Plug.Router
  import Plug.Conn
  alias WandererNotifier.Config.Debug
  alias WandererNotifier.Config.Features
  alias WandererNotifier.Core.Stats
  alias WandererNotifier.License.Service, as: License
  alias WandererNotifier.Logger.Logger, as: AppLogger
  alias WandererNotifier.Schedulers.Registry, as: SchedulerRegistry

  # This controller handles debug endpoints

  # Enables basic plug functionality
  plug(:match)
  plug(:dispatch)

  # GET /debug
  get "/" do
    # Get current debugging state
    current_state = Debug.config().logging_enabled
    debug_enabled = current_state == true

    conn
    |> put_resp_content_type("text/html")
    |> send_resp(200, debug_page_html(debug_enabled))
  end

  # POST /debug/toggle - Toggle debug logging
  post "/toggle" do
    # Get current state and toggle it
    current_state = Debug.debug_logging_enabled?()
    new_state = !current_state

    # Apply the new state
    Debug.set_debug_logging(new_state)

    # Log the change
    AppLogger.api_info("Debug logging #{if new_state, do: "enabled", else: "disabled"}")

    # Redirect back to debug page using conn manipulation directly
    conn
    |> put_resp_header("location", "/debug")
    |> send_resp(302, "Redirecting...")
  end

  # GET /scheduler-stats - Get detailed scheduler statistics for the dashboard
  get "/scheduler-stats" do
    # Step 1: Get all schedulers from registry
    scheduler_list =
      try do
        AppLogger.api_debug("Getting schedulers from registry")
        schedulers = SchedulerRegistry.get_all_schedulers()
        AppLogger.api_debug("Got #{length(schedulers)} schedulers")

        # Log each scheduler for debugging
        Enum.each(schedulers, fn s ->
          AppLogger.api_debug("Found scheduler: #{inspect(s.module)}, enabled: #{s.enabled}")
        end)

        schedulers
      rescue
        e ->
          AppLogger.api_error("Error getting schedulers from registry",
            error: inspect(e),
            stacktrace: inspect(Process.info(self(), :current_stacktrace))
          )

          conn
          |> put_resp_content_type("application/json")
          |> send_resp(
            500,
            Jason.encode!(%{error: "Failed to get schedulers from registry: #{inspect(e)}"})
          )

          nil
      end

    # Only continue if we got schedulers
    if scheduler_list != nil do
      # Step 2: Process each scheduler
      scheduler_info =
        try do
          AppLogger.api_debug("Processing #{length(scheduler_list)} schedulers")

          processed_schedulers =
            Enum.reduce_while(scheduler_list, [], fn scheduler_data, acc ->
              # Always create a basic info map with minimal information that's guaranteed to work
              module = scheduler_data.module

              basic_info = %{
                id: module |> to_string() |> String.replace("Elixir.", ""),
                module: inspect(module),
                name: get_scheduler_name(module),
                enabled: scheduler_data.enabled,
                config: sanitize_config(scheduler_data.config),
                type: get_scheduler_type(scheduler_data.config)
              }

              # Now try to enhance it with detailed information
              try do
                AppLogger.api_debug("Processing scheduler: #{inspect(module)}")

                # Get health info from the scheduler if available
                health_info =
                  if function_exported?(module, :health_check, 0) do
                    try do
                      # Get health info and sanitize it for JSON encoding
                      health_info = module.health_check()
                      sanitize_map_for_json(health_info)
                    rescue
                      e ->
                        # Log more detailed error to help diagnose the issue
                        stack = Process.info(self(), :current_stacktrace)

                        AppLogger.api_error("Error getting health info for #{inspect(module)}",
                          error: inspect(e),
                          error_type: e.__struct__,
                          stacktrace: inspect(stack)
                        )

                        # Return minimal health info instead of empty map
                        %{
                          name: inspect(module),
                          enabled:
                            if(function_exported?(module, :enabled?, 0),
                              do: module.enabled?(),
                              else: false
                            ),
                          error: "Failed to get health info: #{inspect(e)}"
                        }
                    end
                  else
                    # If no health_check function, create basic info from available data
                    %{
                      name: inspect(module),
                      enabled:
                        if(function_exported?(module, :enabled?, 0),
                          do: module.enabled?(),
                          else: false
                        )
                    }
                  end

                # Extract scheduler type from config
                scheduler_type = basic_info.type

                # Extract interval, hour, minute from config safely
                interval = basic_info.config[:interval_ms] || basic_info.config[:interval]
                hour = basic_info.config[:hour]
                minute = basic_info.config[:minute]

                # Process health info into format needed by dashboard
                processed =
                  Map.merge(basic_info, %{
                    interval: interval,
                    hour: hour,
                    minute: minute,
                    last_run: get_formatted_timestamp(health_info[:last_execution]),
                    next_run: calculate_next_run(health_info, scheduler_type, basic_info.config),
                    stats: %{
                      # Will need to implement tracking for this
                      success_count: 0,
                      # Will need to implement tracking for this
                      error_count: 0,
                      last_duration_ms: 0,
                      last_result: health_info[:last_result],
                      last_error: health_info[:last_error],
                      retry_count: health_info[:retry_count] || 0
                    }
                  })

                {:cont, [processed | acc]}
              rescue
                e ->
                  AppLogger.api_error(
                    "Error processing detailed info for scheduler #{inspect(module)}",
                    error: inspect(e),
                    stacktrace: inspect(Process.info(self(), :current_stacktrace))
                  )

                  # Still add the basic information so we at least show the scheduler
                  basic_processed =
                    Map.merge(basic_info, %{
                      error: "Failed to process detailed info: #{inspect(e)}",
                      stats: %{
                        success_count: 0,
                        error_count: 0,
                        last_duration_ms: 0
                      }
                    })

                  {:cont, [basic_processed | acc]}
              end
            end)

          # Reverse the list to maintain original order
          Enum.reverse(processed_schedulers)
        rescue
          e ->
            stacktrace = Process.info(self(), :current_stacktrace)

            AppLogger.api_error("Error processing schedulers",
              error: inspect(e),
              stacktrace: inspect(stacktrace)
            )

            conn
            |> put_resp_content_type("application/json")
            |> send_resp(
              500,
              Jason.encode!(%{
                error: "Failed to process schedulers: #{inspect(e)}",
                details: inspect(e),
                stacktrace: inspect(stacktrace)
              })
            )

            nil
        end

      # Only continue if scheduler processing succeeded
      if scheduler_info != nil do
        # Step 3: Calculate summary and prepare response
        try do
          AppLogger.api_debug("Calculating summary statistics")

          # Calculate summary statistics
          enabled_count = Enum.count(scheduler_info, & &1.enabled)
          interval_count = Enum.count(scheduler_info, &(&1.type == "interval"))
          time_count = Enum.count(scheduler_info, &(&1.type == "time"))

          summary = %{
            total: length(scheduler_info),
            enabled: enabled_count,
            disabled: length(scheduler_info) - enabled_count,
            by_type: %{
              interval: interval_count,
              time: time_count
            }
          }

          # Return JSON response with scheduler info and summary
          response_data = %{
            schedulers: scheduler_info,
            summary: summary
          }

          conn
          |> put_resp_content_type("application/json")
          |> send_resp(200, Jason.encode!(response_data))
        rescue
          e ->
            stacktrace = Process.info(self(), :current_stacktrace)

            AppLogger.api_error("Error generating response data",
              error: inspect(e),
              stacktrace: inspect(stacktrace)
            )

            conn
            |> put_resp_content_type("application/json")
            |> send_resp(
              500,
              Jason.encode!(%{
                error: "Failed to generate response data: #{inspect(e)}",
                details: inspect(e),
                stacktrace: inspect(stacktrace)
              })
            )
        end
      end
    end
  end

  # GET /schedulers - Get raw scheduler data (simpler format)
  get "/schedulers" do
    try do
      # Get all schedulers from registry
      scheduler_list = SchedulerRegistry.get_all_schedulers()

      conn
      |> put_resp_content_type("application/json")
      |> send_resp(200, Jason.encode!(scheduler_list))
    rescue
      e ->
        AppLogger.api_error("Error fetching raw scheduler data", error: inspect(e))

        conn
        |> put_resp_content_type("application/json")
        |> send_resp(500, Jason.encode!(%{error: "Failed to get schedulers: #{inspect(e)}"}))
    end
  end

  # POST /schedulers/execute - Execute all schedulers
  post "/schedulers/execute" do
    try do
      # Trigger execution of all schedulers
      :ok = GenServer.cast(SchedulerRegistry, :execute_all)

      conn
      |> put_resp_content_type("application/json")
      |> send_resp(200, Jason.encode!(%{success: true, message: "All schedulers executed"}))
    rescue
      e ->
        AppLogger.api_error("Error executing schedulers", error: inspect(e))

        conn
        |> put_resp_content_type("application/json")
        |> send_resp(500, Jason.encode!(%{error: "Failed to execute schedulers: #{inspect(e)}"}))
    end
  end

  # POST /scheduler/:id/execute - Execute a specific scheduler
  post "/scheduler/:id/execute" do
    scheduler_name = conn.params["id"]

    if scheduler_name do
      # Try to find the scheduler module
      module_name = "Elixir.WandererNotifier.Schedulers.#{scheduler_name}"

      try do
        # Convert string to module atom
        module = String.to_existing_atom(module_name)

        # Check if the module exists and has execute_now function
        if Code.ensure_loaded?(module) && function_exported?(module, :execute_now, 0) do
          module.execute_now()

          conn
          |> put_resp_content_type("application/json")
          |> send_resp(200, Jason.encode!(%{success: true, message: "Scheduler executed"}))
        else
          conn
          |> put_resp_content_type("application/json")
          |> send_resp(404, Jason.encode!(%{error: "Scheduler not found or cannot be executed"}))
        end
      rescue
        _ ->
          conn
          |> put_resp_content_type("application/json")
          |> send_resp(404, Jason.encode!(%{error: "Scheduler not found"}))
      end
    else
      conn
      |> put_resp_content_type("application/json")
      |> send_resp(400, Jason.encode!(%{error: "Scheduler ID is required"}))
    end
  end

  # GET /scheduler/:id/health - Get health info for a specific scheduler
  get "/scheduler/:id/health" do
    scheduler_name = conn.params["id"]

    if scheduler_name do
      # Try to find the scheduler module
      module_name = "Elixir.WandererNotifier.Schedulers.#{scheduler_name}"

      try do
        # Convert string to module atom
        module = String.to_existing_atom(module_name)

        # Just return all available info about the module to help debug
        functions_map =
          module.__info__(:functions)
          |> Enum.map(fn {k, v} -> "#{k}/#{v}" end)

        conn
        |> put_resp_content_type("application/json")
        |> send_resp(
          200,
          Jason.encode!(%{
            module: inspect(module),
            exists: Code.ensure_loaded?(module),
            has_health_check: function_exported?(module, :health_check, 0),
            functions: functions_map,
            config:
              if(function_exported?(module, :get_config, 0), do: module.get_config(), else: nil),
            enabled:
              if(function_exported?(module, :enabled?, 0), do: module.enabled?(), else: nil)
          })
        )
      rescue
        e ->
          conn
          |> put_resp_content_type("application/json")
          |> send_resp(
            500,
            Jason.encode!(%{
              error: "Error getting scheduler info",
              details: inspect(e),
              stacktrace: inspect(Process.info(self(), :current_stacktrace))
            })
          )
      end
    else
      conn
      |> put_resp_content_type("application/json")
      |> send_resp(400, Jason.encode!(%{error: "Scheduler ID is required"}))
    end
  end

  # GET /debug-scheduler/:name - Debug a specific scheduler
  get "/debug-scheduler/:name" do
    name = conn.params["name"]
    full_module_name = "Elixir.WandererNotifier.Schedulers.#{name}Scheduler"

    try do
      module = String.to_existing_atom(full_module_name)

      # Check if various functions exist
      debug_info =
        if function_exported?(module, :__debug_info__, 0) do
          module.__debug_info__()
        else
          functions_map =
            module.__info__(:functions)
            |> Enum.map(fn {k, v} -> "#{k}/#{v}" end)

          %{
            functions: functions_map,
            exports_health_check: function_exported?(module, :health_check, 0),
            exports_get_config: function_exported?(module, :get_config, 0),
            exports_enabled: function_exported?(module, :enabled?, 0)
          }
        end

      # Try to get config if possible
      config =
        if function_exported?(module, :get_config, 0) do
          try do
            module.get_config()
          rescue
            e -> %{error: inspect(e)}
          end
        else
          nil
        end

      # Try to call health_check if available
      health =
        if function_exported?(module, :health_check, 0) do
          try do
            module.health_check()
          rescue
            e -> %{error: inspect(e)}
          end
        else
          nil
        end

      conn
      |> put_resp_content_type("application/json")
      |> send_resp(
        200,
        Jason.encode!(%{
          module: inspect(module),
          debug_info: debug_info,
          config: config,
          health: health
        })
      )
    rescue
      e ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(
          500,
          Jason.encode!(%{
            error: "Error debugging scheduler",
            details: inspect(e),
            stacktrace: inspect(Process.info(self(), :current_stacktrace))
          })
        )
    end
  end

  # Helper to generate debug page HTML
  defp debug_page_html(debug_enabled) do
    """
    <!DOCTYPE html>
    <html>
      <head>
        <title>Wanderer Notifier Debug</title>
        <style>
          body {
            font-family: Arial, sans-serif;
            max-width: 800px;
            margin: 0 auto;
            padding: 20px;
          }
          h1 {
            color: #333;
          }
          .status {
            font-weight: bold;
            color: #{if debug_enabled, do: "green", else: "red"};
          }
          button {
            padding: 8px 16px;
            margin: 10px 0;
            cursor: pointer;
          }
          pre {
            background-color: #f4f4f4;
            padding: 10px;
            border-radius: 4px;
            overflow-x: auto;
          }
        </style>
      </head>
      <body>
        <h1>Wanderer Notifier Debug Panel</h1>
        <p>Debug logging is currently <span class="status">#{if debug_enabled, do: "ENABLED", else: "DISABLED"}</span></p>
        <form method="post" action="/debug/toggle">
          <button type="submit">#{if debug_enabled, do: "Disable", else: "Enable"} Debug Logging</button>
        </form>

        <h2>System Information</h2>
        <pre>#{Jason.encode!(system_info(), pretty: true)}</pre>
      </body>
    </html>
    """
  end

  # Get system information for debugging
  defp system_info do
    %{
      version: "1.0.0",
      features: Features.get_feature_status(),
      license: License.status(),
      stats: Stats.get_stats(),
      debug_enabled: Debug.config().logging_enabled
    }
  end

  # Helper functions for scheduler stats

  # Determine scheduler type based on config
  defp get_scheduler_type(config) do
    cond do
      Map.has_key?(config, :interval_ms) || Map.has_key?(config, :interval) -> "interval"
      Map.has_key?(config, :hour) && Map.has_key?(config, :minute) -> "time"
      true -> "unknown"
    end
  end

  # Extract name from module
  defp get_scheduler_name(module) do
    module
    |> to_string()
    |> String.replace("Elixir.WandererNotifier.Schedulers.", "")
    |> String.replace("Scheduler", "")
    |> then(fn name ->
      name
      |> String.split(~r/(?=[A-Z])/)
      |> Enum.join(" ")
      |> String.trim()
    end)
  end

  # Format timestamp for last run
  defp get_formatted_timestamp(nil), do: nil
  defp get_formatted_timestamp(timestamp) when not is_integer(timestamp), do: nil

  defp get_formatted_timestamp(timestamp) when is_integer(timestamp) do
    # Convert epoch milliseconds to datetime
    {:ok, datetime} = DateTime.from_unix(div(timestamp, 1000), :second)
    formatted = DateTime.to_iso8601(datetime)

    # Calculate relative time string
    now = DateTime.utc_now()
    diff_seconds = DateTime.diff(now, datetime, :second)

    relative =
      cond do
        diff_seconds < 60 -> "Just now"
        diff_seconds < 3600 -> "#{div(diff_seconds, 60)} minutes ago"
        diff_seconds < 86_400 -> "#{div(diff_seconds, 3600)} hours ago"
        true -> "#{div(diff_seconds, 86_400)} days ago"
      end

    %{
      timestamp: formatted,
      relative: relative
    }
  rescue
    _ -> nil
  end

  # Calculate next run time based on scheduler type
  defp calculate_next_run(_health_info, "interval", config) do
    # For interval schedulers, next run is roughly now + interval
    interval_ms = config[:interval_ms] || config[:interval]

    if interval_ms && is_integer(interval_ms) do
      now = DateTime.utc_now()
      # Add interval (approximate since we don't know exact last execution time)
      next_run_time = DateTime.add(now, div(interval_ms, 1000), :second)

      format_relative_time(next_run_time, now)
    else
      nil
    end
  rescue
    _ -> nil
  end

  defp calculate_next_run(_health_info, "time", config) do
    # For time schedulers, calculate next occurrence based on hour and minute
    hour = config[:hour]
    minute = config[:minute]

    if hour && minute && is_integer(hour) && is_integer(minute) do
      now = DateTime.utc_now()

      # Calculate next run time
      next_run_time = calculate_next_time_scheduler_run(now, hour, minute)

      format_relative_time(next_run_time, now)
    else
      nil
    end
  rescue
    _ -> nil
  end

  defp calculate_next_run(_health_info, _type, _config), do: nil

  # Helper function to calculate the next run time for time schedulers
  defp calculate_next_time_scheduler_run(now, hour, minute) do
    current_hour = now.hour
    current_minute = now.minute

    # Determine if next run is today or tomorrow
    {next_day, next_hour, next_minute} =
      if current_hour < hour || (current_hour == hour && current_minute < minute) do
        # If current time is before scheduled time today
        {now.day, hour, minute}
      else
        # If current time is after scheduled time, next is tomorrow
        {now.day + 1, hour, minute}
      end

    # Create next run datetime
    next_run_time = %DateTime{
      year: now.year,
      month: now.month,
      day: next_day,
      hour: next_hour,
      minute: next_minute,
      second: 0,
      microsecond: {0, 0},
      time_zone: "Etc/UTC",
      zone_abbr: "UTC",
      utc_offset: 0,
      std_offset: 0
    }

    # Handle month rollover
    if next_day > Date.days_in_month(now) do
      %{next_run_time | day: 1, month: rem(now.month, 12) + 1}
    else
      next_run_time
    end
  end

  # Helper function to format the relative time for display
  defp format_relative_time(datetime, now) do
    formatted = DateTime.to_iso8601(datetime)
    diff_seconds = DateTime.diff(datetime, now, :second)

    relative =
      cond do
        diff_seconds < 60 -> "In a few seconds"
        diff_seconds < 3600 -> "In #{div(diff_seconds, 60)} minutes"
        diff_seconds < 86_400 -> "In #{div(diff_seconds, 3600)} hours"
        true -> "In #{div(diff_seconds, 86_400)} days"
      end

    %{
      timestamp: formatted,
      relative: relative
    }
  end

  # Match all other routes
  match _ do
    send_resp(conn, 404, "Not found")
  end

  def status(conn, _params) do
    debug_config = Debug.config()

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(
      200,
      Jason.encode!(%{
        success: true,
        debug_enabled: debug_config.logging_enabled,
        map_debug: debug_config.map_settings
      })
    )
  end

  # Helper function to sanitize config for JSON encoding
  defp sanitize_config(config) do
    sanitize_map_for_json(config)
  end

  # Helper function to sanitize map for JSON encoding
  defp sanitize_map_for_json(map) when is_map(map) do
    # Filter out any potentially unencodable values
    map
    |> Enum.map(fn {k, v} ->
      {k, sanitize_value(v)}
    end)
    |> Map.new()
  end

  defp sanitize_map_for_json(value), do: sanitize_value(value)

  # Function to sanitize individual values
  defp sanitize_value(v) when is_map(v), do: sanitize_map_for_json(v)
  defp sanitize_value(v) when is_list(v), do: Enum.map(v, &sanitize_value/1)
  defp sanitize_value(v) when is_atom(v), do: Atom.to_string(v)
  defp sanitize_value(v) when is_pid(v), do: inspect(v)
  defp sanitize_value(v) when is_function(v), do: "#Function<...>"
  defp sanitize_value(v) when is_tuple(v), do: sanitize_tuple(v)
  defp sanitize_value(v) when is_binary(v) or is_number(v) or is_boolean(v) or is_nil(v), do: v
  defp sanitize_value(v) when is_reference(v), do: inspect(v)
  defp sanitize_value(_), do: "#Unencodable<...>"

  # Handle tuples by converting them to lists and sanitizing each element
  defp sanitize_tuple(tuple) do
    tuple
    |> Tuple.to_list()
    |> Enum.map(&sanitize_value/1)
    |> List.to_tuple()
  rescue
    # If there's any error sanitizing the tuple, convert to string
    _ -> inspect(tuple)
  end
end
