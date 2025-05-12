defmodule WandererNotifier.Notifications.NotificationService do
  @moduledoc """
  Service module for handling notification dispatch.
  """

  alias WandererNotifier.Notifications.Types.Notification
  alias WandererNotifier.Notifications.Dispatcher
  alias WandererNotifier.Logger.Logger, as: AppLogger

  @doc """
  Sends a notification.

  ## Parameters
    - notification: The notification to send

  ## Returns
    - {:ok, notification} on success
    - {:error, reason} on failure
  """
  def send(%Notification{} = notification) do
    try do
      AppLogger.info("Sending notification", %{type: notification.type})

      # Set a standardized notification type for the kill notification
      notification = %{notification | type: standardize_notification_type(notification.type)}

      # Use the dispatcher to send the notification
      case Dispatcher.send_message(notification) do
        {:ok, :sent} ->
          AppLogger.kill_info("Successfully dispatched notification", %{type: notification.type})
          {:ok, notification}

        {:error, reason} = error ->
          AppLogger.kill_error(
            "Failed to dispatch notification",
            %{type: notification.type, reason: inspect(reason)}
          )

          error
      end
    rescue
      e ->
        AppLogger.kill_error(
          "Exception in NotificationService.send",
          %{error: Exception.message(e), stacktrace: Exception.format_stacktrace(__STACKTRACE__)}
        )

        {:error, :notification_service_error}
    end
  end

  def send(_), do: {:error, :invalid_notification}

  # Convert string notification types to atoms for consistent processing
  defp standardize_notification_type("kill"), do: :kill_notification
  defp standardize_notification_type("test"), do: :kill_notification
  defp standardize_notification_type("system"), do: :system_notification
  defp standardize_notification_type("character"), do: :character_notification
  defp standardize_notification_type("status"), do: :status_notification
  defp standardize_notification_type(type) when is_atom(type), do: type
  defp standardize_notification_type(_), do: :unknown
end
