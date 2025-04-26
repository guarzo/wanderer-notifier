defmodule WandererNotifier.Api.Controllers.NotificationController do
  @moduledoc """
  Controller for notification-related endpoints.
  """
  use WandererNotifier.Api.Controller

  alias WandererNotifier.Config.Features
  alias WandererNotifier.Config.Notifications, as: NotificationConfig
  alias WandererNotifier.Logger.Logger, as: AppLogger
  alias WandererNotifier.Notifiers.Helpers.TestNotifications, as: NotificationHelpers

  # Get notification settings
  get "/settings" do
    case get_notification_settings(conn) do
      {:ok, settings} ->
        send_success(conn, settings)

      {:error, reason} ->
        AppLogger.api_error("Error getting notification settings", reason)
        send_error(conn, 500, "Internal server error")
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
      {:ok, _} -> send_success(conn, %{message: "Test notification sent"})
      {:error, reason} -> send_error(conn, 400, reason)
    end
  end

  match _ do
    send_error(conn, 404, "Not found")
  end

  # Private functions

  defp get_notification_settings(conn) do
    settings = %{
      channels: NotificationConfig.get_discord_config(),
      features: Features.get_feature_status(),
      limits: Features.get_all_limits()
    }

    {:ok, settings}
  rescue
    error ->
      AppLogger.api_error("Error getting notification settings", %{
        error: inspect(error),
        stacktrace: Exception.format_stacktrace(__STACKTRACE__)
      })

      send_error(conn, 500, "An unexpected error occurred")
  end
end
