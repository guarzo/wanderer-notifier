defmodule WandererNotifier.Processing.Killmail.Notification do
  @moduledoc """
  Handles sending notifications for killmails.

  This module provides a clean interface for sending notifications for killmails
  to various notification channels.
  """

  alias WandererNotifier.KillmailProcessing.KillmailData
  alias WandererNotifier.Logger.Logger, as: AppLogger
  alias WandererNotifier.Notifiers.Discord.Notifier, as: DiscordNotifier

  @doc """
  Sends a notification for a killmail.

  ## Parameters
    - killmail: The KillmailData struct to notify about
    - kill_id: The ID of the killmail (for logging)

  ## Returns
    - {:ok, result} if notification is sent successfully
    - {:error, reason} if an error occurs
  """
  @spec send_kill_notification(KillmailData.t(), integer()) :: {:ok, any()} | {:error, any()}
  def send_kill_notification(%KillmailData{} = killmail, kill_id) do
    AppLogger.kill_debug("Sending notification for killmail ##{kill_id}")

    # Delegate to the Discord notifier which handles rich formatting and delivery
    try do
      DiscordNotifier.send_enriched_kill_embed(killmail, kill_id)
    rescue
      e ->
        AppLogger.kill_error("Error sending notification: #{Exception.message(e)}")
        {:error, :notification_error}
    end
  end

  def send_kill_notification(other, kill_id) do
    AppLogger.kill_error("Cannot send notification for non-KillmailData: #{inspect(other)}")
    {:error, :invalid_data_type}
  end
end
