defmodule WandererNotifier.Api.Controllers.NotificationController do
  @moduledoc """
  Controller for notification-related endpoints.
  """
  use WandererNotifier.Api.ApiPipeline
  use WandererNotifier.Api.Controllers.ControllerHelpers
  import WandererNotifier.Api.Helpers

  alias WandererNotifier.Config
  alias WandererNotifier.Logger.Logger, as: AppLogger
  alias WandererNotifier.Notifiers.TestNotifier, as: NotificationHelpers

  # Get notification settings
  get "/settings" do
    case get_notification_settings() do
      {:ok, settings} -> send_success(conn, settings)
      {:error, "not_found"} -> send_error(conn, 404, "Notification settings not found")
      {:error, reason} -> send_error(conn, 500, reason)
    end
  end

  # Send test notification
  post "/test" do
    type = conn.body_params["type"] || "kill"

    with {:ok, notification_type} <- validate_notification_type(type),
         {:ok, _} <- send_test_notification(notification_type) do
      send_success(conn, %{message: "Test notification sent"})
    else
      {:error, reason} -> send_error(conn, 400, reason)
    end
  end

  match _ do
    send_error(conn, 404, "not_found")
  end

  # Private functions
  defp validate_notification_type(type) do
    case type do
      "kill" -> {:ok, :kill}
      "character" -> {:ok, :character}
      "system" -> {:ok, :system}
      _ -> {:error, "Invalid notification type"}
    end
  end

  defp send_test_notification(:kill), do: NotificationHelpers.send_test_kill_notification()

  defp send_test_notification(:character),
    do: NotificationHelpers.send_test_character_notification()

  defp send_test_notification(:system), do: NotificationHelpers.send_test_system_notification()

  defp get_notification_settings do
    features =
      Config.features()
      # fall back to empty list
      |> Kernel.||([])

    features_map = Enum.into(features, %{})

    settings = %{
      channels: Config.discord_channel_id(),
      features: features_map,
      limits: Config.get_all_limits()
    }

    {:ok, settings}
  rescue
    error ->
      AppLogger.api_error("Error getting notification settings", %{
        error: inspect(error),
        stacktrace: Exception.format(:error, error, __STACKTRACE__),
        context: "get_notification_settings"
      })

      {:error, "An unexpected error occurred while retrieving notification settings"}
  end
end
