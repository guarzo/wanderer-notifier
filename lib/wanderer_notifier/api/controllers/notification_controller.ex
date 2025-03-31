defmodule WandererNotifier.Api.Controllers.NotificationController do
  @moduledoc """
  Controller for notification-related endpoints.
  """
  use Plug.Router
  import Plug.Conn

  alias WandererNotifier.Config.Features
  alias WandererNotifier.Config.Notifications, as: NotificationConfig
  alias WandererNotifier.Helpers.NotificationHelpers
  alias WandererNotifier.Logger.Logger, as: AppLogger

  plug(Plug.Parsers,
    parsers: [:json],
    pass: ["application/json"],
    json_decoder: Jason
  )

  plug(:match)
  plug(:dispatch)

  # Get notification settings
  get "/settings" do
    case get_notification_settings() do
      {:ok, settings} ->
        send_json_response(conn, 200, settings)

      {:error, reason} ->
        AppLogger.api_error("Error getting notification settings", reason)
        send_json_response(conn, 500, %{error: "Internal server error"})
    end
  end

  # Send test notification
  post "/test" do
    type = conn.body_params["type"] || "kill"

    result =
      case type do
        "kill" -> NotificationHelpers.send_test_kill_notification()
        "character" -> NotificationHelpers.send_test_character_notification()
        "system" -> NotificationHelpers.send_test_system_notification()
        _ -> {:error, "Invalid notification type"}
      end

    case result do
      {:ok, _} -> send_json_response(conn, 200, %{message: "Test notification sent"})
      {:error, reason} -> send_json_response(conn, 400, %{error: reason})
    end
  end

  match _ do
    send_json_response(conn, 404, %{error: "Not found"})
  end

  # Private functions

  defp get_notification_settings do
    settings = %{
      channels: NotificationConfig.get_discord_config(),
      features: Features.get_feature_status(),
      limits: Features.get_all_limits()
    }

    {:ok, settings}
  rescue
    error ->
      {:error, %{error: inspect(error), stacktrace: Exception.format_stacktrace(__STACKTRACE__)}}
  end

  defp send_json_response(conn, status, body) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(body))
  end
end
