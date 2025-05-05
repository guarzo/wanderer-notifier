defmodule WandererNotifier.Killmail.Notification do
  @moduledoc """
  Handles sending notifications for killmails.
  """

  alias WandererNotifier.Logger.Logger, as: AppLogger
  alias WandererNotifier.Notifications.Dispatcher
  alias WandererNotifier.Notifications.KillmailNotification

  @doc """
  Sends a notification for a killmail.

  ## Parameters
    - killmail: The killmail data to send a notification for
    - kill_id: The ID of the kill for logging purposes

  ## Returns
    - {:ok, notification_result} on success
    - {:error, reason} on failure
  """
  def send_kill_notification(killmail, kill_id) do
    try do
      # Create the notification using the KillmailNotification module
      notification = KillmailNotification.create(killmail)

      # Send the notification through the factory
      case Dispatcher.send_message(notification) do
        {:ok, :sent} ->
          AppLogger.notification_info("Kill notification sent successfully", %{
            kill_id: kill_id,
            victim: killmail.victim_name,
            attacker: killmail.attacker_name
          })

          {:ok, notification}

        {:error, :notifications_disabled} ->
          AppLogger.notification_info("Kill notification skipped - notifications disabled", %{
            kill_id: kill_id
          })

          {:ok, :disabled}

        {:error, reason} = error ->
          AppLogger.notification_error("Failed to send kill notification", %{
            kill_id: kill_id,
            error: inspect(reason)
          })

          error
      end
    rescue
      e ->
        AppLogger.notification_error("Exception sending kill notification", %{
          kill_id: kill_id,
          error: Exception.message(e),
          stacktrace: Exception.format_stacktrace(__STACKTRACE__)
        })

        {:error, :notification_failed}
    end
  end
end
