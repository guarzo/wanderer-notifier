defmodule WandererNotifier.Killmail.Notification do
  @moduledoc """
  Handles sending notifications for killmails.
  """

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
      notification = killmail_notification_module().create(killmail)

      # Send the notification through the dispatcher
      case dispatcher_module().send_message(notification) do
        {:ok, :sent} ->
          {:ok, notification}

        {:error, :notifications_disabled} ->
          {:ok, :disabled}

        {:error, reason} = error ->
          logger_module().notification_error("Failed to send kill notification", %{
            kill_id: kill_id,
            error: inspect(reason)
          })

          error
      end
    rescue
      e ->
        logger_module().notification_error("Exception sending kill notification", %{
          kill_id: kill_id,
          error: Exception.message(e),
          stacktrace: Exception.format_stacktrace(__STACKTRACE__)
        })

        {:error, :notification_failed}
    end
  end

  # Get the appropriate module from application config or use the default
  defp killmail_notification_module do
    Application.get_env(
      :wanderer_notifier,
      :killmail_notification_module,
      WandererNotifier.Notifications.KillmailNotification
    )
  end

  defp dispatcher_module do
    Application.get_env(
      :wanderer_notifier,
      :dispatcher_module,
      WandererNotifier.Notifications.Dispatcher
    )
  end

  defp logger_module do
    Application.get_env(
      :wanderer_notifier,
      :logger_module,
      WandererNotifier.Logger.Logger
    )
  end
end
