defmodule WandererNotifier.Notifications.NotificationService do
  @moduledoc """
  Service module for handling notification dispatch.
  """

  alias WandererNotifier.Notifications.Types.Notification
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
    AppLogger.info("Sending notification", %{type: notification.type})

    # Here we would implement the actual notification sending logic
    # For now, we'll just return success
    {:ok, notification}
  end

  def send(_), do: {:error, :invalid_notification}
end
