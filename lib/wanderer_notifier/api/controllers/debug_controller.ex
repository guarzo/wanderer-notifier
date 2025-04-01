defmodule WandererNotifier.Api.Controllers.DebugController do
  @moduledoc """
  Controller for debug-related endpoints.
  """
  use WandererNotifier.Api.Controllers.BaseController

  alias WandererNotifier.Config.Features
  alias WandererNotifier.Core.Stats
  alias WandererNotifier.Data.Repo
  alias WandererNotifier.License.Service, as: License
  alias WandererNotifier.Logger.Logger, as: AppLogger
  alias WandererNotifier.Resources.TrackedCharacter

  # Get service status
  get "/status" do
    case get_service_status(conn) do
      {:ok, response} ->
        send_success_response(conn, response)

      {:error, reason} ->
        AppLogger.api_error("Error getting debug status", reason)
        send_error_response(conn, 500, "Internal server error")
    end
  end

  # Get database stats
  get "/db-stats" do
    if TrackedCharacter.database_enabled?() do
      try do
        # Check total killmail records
        killmail_query = "SELECT COUNT(*) FROM killmails"
        {:ok, %{rows: [[total_killmails]]}} = Repo.query(killmail_query)

        # Count tracked characters in database
        char_query = "SELECT COUNT(*) FROM tracked_characters"
        {:ok, %{rows: [[total_chars]]}} = Repo.query(char_query)

        # Get database health
        {:ok, ping_ms} = Repo.health_check()

        send_success_response(conn, %{
          killmail: %{
            total_kills: total_killmails,
            tracked_characters: total_chars
          },
          db_health: %{
            status: "connected",
            ping_ms: ping_ms
          }
        })
      rescue
        e ->
          AppLogger.api_error("Error getting database stats", error: Exception.message(e))
          send_error_response(conn, 500, "Error retrieving database statistics")
      end
    else
      send_success_response(conn, %{
        killmail: %{
          total_kills: 0,
          tracked_characters: 0
        },
        db_health: %{
          status: "disabled"
        }
      })
    end
  end

  # Get service stats
  get "/stats" do
    stats = get_stats_safely()
    send_success_response(conn, stats)
  end

  # Get scheduler stats
  get "/scheduler-stats" do
    scheduler_info = WandererNotifier.Schedulers.Registry.get_all_schedulers()

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

    send_success_response(conn, %{
      schedulers: formatted_schedulers,
      summary: %{
        total: length(formatted_schedulers),
        enabled: Enum.count(formatted_schedulers, & &1.enabled),
        disabled: Enum.count(formatted_schedulers, &(!&1.enabled))
      }
    })
  end

  match _ do
    send_error_response(conn, 404, "Not found")
  end

  # Private functions

  defp get_service_status(conn) do
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
    features = Features.get_feature_status()
    limits = get_limits_safely()

    # Build response
    {:ok,
     %{
       license: license_status,
       stats: stats,
       features: features,
       limits: limits
     }}
  rescue
    error -> handle_error(conn, error, __MODULE__)
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

  defp get_limits_safely do
    result = Features.get_all_limits()
    AppLogger.api_info("Retrieved limits", %{limits: inspect(result)})
    result
  rescue
    error ->
      AppLogger.api_error("Error getting limits", %{
        error: inspect(error),
        stacktrace: Exception.format_stacktrace(__STACKTRACE__)
      })

      %{tracked_systems: 0, tracked_characters: 0, notification_history: 0}
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
        last_message: nil,
        messages_received: 0,
        messages_processed: 0,
        errors: 0
      }
    }
  end
end
