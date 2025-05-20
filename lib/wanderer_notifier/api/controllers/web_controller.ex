defmodule WandererNotifier.Api.Controllers.WebController do
  @moduledoc """
  Controller for web-related endpoints and application status management.
  Provides endpoints for service status, statistics, and scheduler management.
  """
  use WandererNotifier.Api.ApiPipeline
  use WandererNotifier.Api.Controllers.ControllerHelpers
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
    formatted_schedulers = format_schedulers(scheduler_info)

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
        |> String.replace("Scheduler", "")
        |> String.downcase() == String.downcase(scheduler_name)
      end)

    case scheduler_module do
      %{module: module, enabled: true} ->
        # Execute the scheduler asynchronously
        Task.Supervisor.start_child(
          WandererNotifier.TaskSupervisor,
          fn ->
            AppLogger.api_info("Running scheduler in background", %{module: inspect(module)})
            module.run()
          end
        )

        send_success(conn, %{message: "Scheduler execution triggered in background"})

      %{enabled: false} ->
        send_error(conn, 400, "Scheduler is disabled")

      nil ->
        send_error(conn, 404, "Scheduler not found")
    end
  end

  # Execute all schedulers
  post "/schedulers/execute" do
    # Create supervised tasks for each enabled scheduler
    WandererNotifier.Schedulers.Registry.all_schedulers()
    |> Enum.filter(fn %{enabled: enabled} -> enabled end)
    |> Enum.each(fn %{module: module} ->
      # Start a supervised background task for each scheduler
      Task.Supervisor.start_child(
        WandererNotifier.TaskSupervisor,
        fn ->
          AppLogger.api_info("Running scheduler in background", %{module: inspect(module)})

          try do
            module.run()
          rescue
            e ->
              AppLogger.api_error("Scheduler failed", %{
                module: inspect(module),
                error: Exception.message(e),
                stacktrace: Exception.format(:error, e, __STACKTRACE__)
              })
          end
        end
      )
    end)

    send_success(conn, %{message: "All schedulers execution triggered in background"})
  end

  match _ do
    send_error(conn, 404, "not_found")
  end

  # Private functions

  defp get_service_status() do
    # Get license status safely
    license_result = License.validate()

    license_status = %{
      valid: license_result.valid,
      bot_assigned: license_result.bot_assigned,
      details: license_result.details,
      error: license_result.error,
      error_message: license_result.error_message,
      last_validated: license_result.last_validated,
      status: if(license_result.valid, do: "valid", else: "invalid")
    }

    # Get stats safely
    stats = get_stats_safely()

    # Get features and transform them for the frontend
    features =
      Config.features()
      |> Enum.into(%{})

    features =
      features
      |> Map.drop([:disable_status_messages])
      |> Map.put(
        :status_messages_enabled,
        !Map.get(features, :disable_status_messages, false)
      )

    limits = Config.get_all_limits()

    # Extract services from stats for easier UI access
    services =
      Map.get(stats, :services, %{
        backend: "running",
        notifications: "running",
        api: "running"
      })

    # Build response
    {:ok,
     %{
       services: services,
       license: license_status,
       stats: stats,
       features: features,
       limits: limits
     }}
  rescue
    error ->
      AppLogger.api_error("Error in service status", %{
        error: inspect(error),
        stacktrace: Exception.format(:error, error, __STACKTRACE__)
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
        stats
    end
  rescue
    error ->
      AppLogger.api_error("Error getting stats", %{
        error: inspect(error),
        stacktrace: Exception.format(:error, error, __STACKTRACE__)
      })

      create_default_stats()
  end

  defp create_default_stats do
    %{
      notifications: %{
        total: 0,
        success: 0,
        failed: 0,
        last_sent: nil
      },
      websocket: %{
        connected: false,
        last_connected: nil,
        last_disconnected: nil,
        reconnect_attempts: 0
      },
      services: %{
        backend: "running",
        notifications: "running",
        api: "running"
      }
    }
  end

  defp format_schedulers(schedulers) do
    Enum.map(schedulers, fn %{module: module, enabled: _enabled} = scheduler ->
      name =
        module
        |> to_string()
        |> String.split(".")
        |> List.last()
        |> String.replace("Scheduler", "")

      Map.merge(scheduler, %{
        name: name,
        display_name: String.replace(name, ~r/([A-Z])/, " \\1") |> String.trim()
      })
    end)
  end
end
