defmodule WandererNotifier.Api.Controllers.DebugController do
  @moduledoc """
  Controller for debug-related endpoints.
  """
  use Plug.Router
  import Plug.Conn

  alias WandererNotifier.Config.Features
  alias WandererNotifier.Core.Stats
  alias WandererNotifier.License.Service, as: License
  alias WandererNotifier.Logger.Logger, as: AppLogger

  plug(Plug.Parsers,
    parsers: [:json],
    pass: ["application/json"],
    json_decoder: Jason
  )

  plug(:match)
  plug(:dispatch)

  # Get service status
  get "/status" do
    case get_service_status() do
      {:ok, response} ->
        send_json_response(conn, 200, response)

      {:error, reason} ->
        AppLogger.api_error("Error getting debug status", reason)
        send_json_response(conn, 500, %{error: "Internal server error"})
    end
  end

  # Get service stats
  get "/stats" do
    stats = get_stats_safely()
    send_json_response(conn, 200, stats)
  end

  match _ do
    send_json_response(conn, 404, %{error: "Not found"})
  end

  # Private functions

  defp get_service_status do
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
    error ->
      {:error, %{error: inspect(error), stacktrace: Exception.format_stacktrace(__STACKTRACE__)}}
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

  defp send_json_response(conn, status, body) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(body))
  end
end
