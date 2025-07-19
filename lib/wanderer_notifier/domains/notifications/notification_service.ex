defmodule WandererNotifier.Domains.Notifications.NotificationService do
  @moduledoc """
  Service module for handling notification dispatch.
  """

  alias WandererNotifier.Domains.Notifications.Types.Notification
  alias WandererNotifier.Domains.Notifications.Dispatcher
  alias WandererNotifier.Shared.Logger.ErrorLogger
  alias WandererNotifier.Shared.Logger.Logger, as: AppLogger

  @doc """
  Sends a notification.

  ## Parameters
    - notification: The notification to send

  ## Returns
    - {:ok, notification} on success
    - {:error, reason} on failure
  """
  def send(%Notification{} = notification) do
    AppLogger.info("Sending notification", %{type: notification.type})

    # Set a standardized notification type for the kill notification
    notification = %{notification | type: standardize_notification_type(notification.type)}

    # Use the dispatcher to send the notification
    case safe_dispatch(notification) do
      {:ok, :sent} ->
        AppLogger.kill_info("Successfully dispatched notification", %{type: notification.type})
        {:ok, notification}

      {:error, reason} = error ->
        ErrorLogger.log_notification_error(
          "Failed to dispatch notification",
          type: notification.type,
          reason: inspect(reason)
        )

        error

      {:exception, exception, stacktrace} ->
        ErrorLogger.log_exception(
          "Exception in NotificationService.send",
          exception,
          type: notification.type,
          stacktrace: stacktrace
        )

        {:error, :notification_service_error}
    end
  end

  def send(_), do: {:error, :invalid_notification}

  # Wrapper to safely dispatch and catch exceptions
  defp safe_dispatch(notification) do
    Dispatcher.send_message(notification)
  rescue
    exception ->
      {:exception, exception, __STACKTRACE__}
  end

  # Convert string notification types to atoms for consistent processing
  defp standardize_notification_type("kill"), do: :kill_notification
  defp standardize_notification_type("test"), do: :kill_notification
  defp standardize_notification_type("system"), do: :system_notification
  defp standardize_notification_type("character"), do: :character_notification
  defp standardize_notification_type(type) when is_atom(type), do: type
  defp standardize_notification_type(_), do: :unknown
end
