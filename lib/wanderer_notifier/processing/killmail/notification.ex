defmodule WandererNotifier.Processing.Killmail.Notification do
  @moduledoc """
  @deprecated Please use WandererNotifier.Killmail.Processing.Notification instead

  This module is deprecated and will be removed in a future release.
  All functionality has been moved to WandererNotifier.Killmail.Processing.Notification.
  """

  alias WandererNotifier.Killmail.Core.Data
  alias WandererNotifier.Logger.Logger, as: AppLogger
  alias WandererNotifier.Notifiers.Discord.Notifier, as: DiscordNotifier
  alias WandererNotifier.Killmail.Processing.Notification, as: NewNotification

  @doc """
  Sends a notification for a killmail.
  @deprecated Please use WandererNotifier.Killmail.Processing.Notification.notify/1 instead

  ## Parameters
    - killmail: The KillmailData struct to notify about
    - kill_id: The ID of the killmail (for logging)

  ## Returns
    - {:ok, result} if notification is sent successfully
    - {:error, reason} if an error occurs
  """
  @spec send_kill_notification(Data.t(), integer()) :: {:ok, any()} | {:error, any()}
  def send_kill_notification(%Data{} = killmail, kill_id) do
    AppLogger.kill_debug(
      "Sending notification for killmail ##{kill_id} (using deprecated module)"
    )

    # Delegate to the new notification module
    case NewNotification.notify(killmail) do
      :ok -> {:ok, :sent}
      error -> error
    end
  end

  def send_kill_notification(other, _kill_id) do
    AppLogger.kill_error("Cannot send notification for non-Data: #{inspect(other)}")
    {:error, :invalid_data_type}
  end
end
