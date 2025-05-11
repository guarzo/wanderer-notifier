defmodule WandererNotifier.Api.Controllers.NotificationController do
  @moduledoc """
  Controller for notification-related endpoints.
  """
  use WandererNotifier.Api.ApiPipeline
  import WandererNotifier.Api.Helpers

  alias WandererNotifier.Config
  alias WandererNotifier.Logger.Logger, as: AppLogger
  alias WandererNotifier.Notifiers.TestNotifier, as: NotificationHelpers

  # Get notification settings
  get "/settings" do
    case get_notification_settings() do
      {:ok, settings} -> send_success(conn, settings)
      _error -> send_error(conn, 404, "Notification settings not found or could not be retrieved")
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
    send_error(conn, 404, "not_found")
  end

  # Private functions
  defp get_notification_settings do
    settings = %{
      channels: Config.discord_channel_id(),
      features: Config.features(),
      limits: Config.get_all_limits()
    }

    {:ok, settings}
  rescue
    error ->
      AppLogger.api_error("Error getting notification settings", %{
        error: inspect(error),
        stacktrace: Exception.format(:error, error, __STACKTRACE__)
      })

      {:error, "An unexpected error occurred"}
  end
end
