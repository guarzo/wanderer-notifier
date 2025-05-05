defmodule WandererNotifier.Api.Controllers.WebController do
  @moduledoc """
  Controller for debug-related endpoints.
  """
  use WandererNotifier.Api.ApiPipeline
  import WandererNotifier.Api.Helpers

  alias WandererNotifier.Core.Stats
  alias WandererNotifier.Config
  alias WandererNotifier.License.Service, as: License
  alias WandererNotifier.Logger.Logger, as: AppLogger

  # Get service status
  get "/status" do
    case get_service_status() do
      {:ok, status} -> send_success(conn, status)
      {:error, reason} -> send_error(conn, 500, reason)
    end
  end

  # Get service stats
  get "/stats" do
    stats = get_stats_safely()
    send_success(conn, stats)
  end

  # Get scheduler stats
  get "/scheduler-stats" do
    scheduler_info = WandererNotifier.Schedulers.Registry.all_schedulers()

    # Transform scheduler info into a more friendly format
    formatted_schedulers =
      Enum.map(scheduler_info, fn %{module: module, enabled: enabled, config: config} ->
        name =
          module
          |> to_string()
          |> String.split(".")
          |> List.last()
          |> String.replace("Scheduler", "")

        type = if Map.has_key?(config, :interval), do: "interval", else: "time"

        %{
          name: name,
          type: type,
          enabled: enabled,
          interval: Map.get(config, :interval),
          hour: Map.get(config, :hour),
          minute: Map.get(config, :minute),
          last_run: Map.get(config, :last_run),
          next_run: Map.get(config, :next_run),
          stats:
            Map.get(config, :stats, %{
              success_count: 0,
              error_count: 0,
              last_duration_ms: nil
            })
        }
      end)

    send_success(conn, %{
      schedulers: formatted_schedulers,
      summary: %{
        total: length(formatted_schedulers),
        enabled: Enum.count(formatted_schedulers, & &1.enabled),
        disabled: Enum.count(formatted_schedulers, &(!&1.enabled))
      }
    })
  end

  # Execute a specific scheduler
  post "/schedulers/:name/execute" do
    scheduler_name = conn.params["name"]

    # Find the scheduler module
    scheduler_module =
      WandererNotifier.Schedulers.Registry.all_schedulers()
      |> Enum.find(fn %{module: module} ->
        module
        |> to_string()
        |> String.split(".")
        |> List.last()
        |> String.replace("Scheduler", "") == scheduler_name
      end)

    case scheduler_module do
      %{module: module, enabled: true} ->
        # Execute the scheduler
        module.run()
        send_success(conn, %{message: "Scheduler execution triggered"})

      %{enabled: false} ->
        send_error(conn, 400, "Scheduler is disabled")

      nil ->
        send_error(conn, 404, "Scheduler not found")
    end
  end

  # Execute all schedulers
  post "/schedulers/execute" do
    WandererNotifier.Schedulers.Registry.all_schedulers()
    |> Enum.each(fn %{module: module, enabled: enabled} ->
      if enabled, do: module.run()
    end)

    send_success(conn, %{message: "All schedulers execution triggered"})
  end

  match _ do
    send_error(conn, 404, "not_found")
  end

  # Private functions

  defp get_service_status() do
    AppLogger.api_info("Starting status endpoint processing")

    # Get license status safely
    AppLogger.api_info("Fetching license status")
    license_result = License.validate()
    AppLogger.api_info("License status result", %{result: inspect(license_result)})

    license_status = %{
      valid: license_result.valid,
      bot_assigned: license_result.bot_assigned,
      details: license_result.details,
      error: license_result.error,
      error_message: license_result.error_message,
      last_validated: license_result.last_validated
    }

    # Get stats safely
    AppLogger.api_info("Fetching stats")
    stats = get_stats_safely()

    # Get features and limits
    AppLogger.api_info("Fetching features and limits")
    features = Config.features()
    limits = Config.get_all_limits()

    # Build response
    {:ok,
     %{
       license: license_status,
       stats: stats,
       features: features,
       limits: limits
     }}
  rescue
    error ->
      AppLogger.api_error("Error in debug status", %{
        error: inspect(error),
        stacktrace: Exception.format_stacktrace(__STACKTRACE__)
      })

      {:error, "An unexpected error occurred"}
  end

  defp get_stats_safely do
    case Stats.get_stats() do
      nil ->
        AppLogger.api_warn("Stats.get_stats() returned nil")
        create_default_stats()

      stats when not is_map_key(stats, :notifications) or not is_map_key(stats, :websocket) ->
        AppLogger.api_warn("Stats.get_stats() returned incomplete data: #{inspect(stats)}")
        create_default_stats()

      stats ->
        AppLogger.api_info("Stats retrieved successfully", %{stats: inspect(stats)})
        stats
    end
  rescue
    error ->
      AppLogger.api_error("Error getting stats", %{
        error: inspect(error),
        stacktrace: Exception.format_stacktrace(__STACKTRACE__)
      })

      create_default_stats()
  end

  defp create_default_stats do
    %{
      notifications: %{
        total: 0,
        success: 0,
        error: 0
      },
      websocket: %{
        connected: false,
        last_message: nil
      }
    }
  end
end
