defmodule WandererNotifier.Killmail.Processing.Notification do
  @moduledoc """
  Handles sending notifications for killmails.

  This module provides a clean interface for sending notifications for killmails
  to various notification channels.
  """

  alias WandererNotifier.Killmail.Core.Data, as: KillmailData
  alias WandererNotifier.Logger.Logger, as: AppLogger
  alias WandererNotifier.Notifiers.Discord.Notifier, as: DiscordNotifier

  @doc """
  Sends a notification for a killmail.

  ## Parameters
    - killmail: The KillmailData struct to notify about

  ## Returns
    - :ok if notification is sent successfully
    - {:error, reason} if an error occurs
  """
  @spec notify(KillmailData.t()) :: :ok | {:error, any()}
  def notify(%KillmailData{} = killmail) do
    AppLogger.kill_debug("Sending notification for killmail ##{killmail.killmail_id}")

    # Delegate to the Discord notifier which handles rich formatting and delivery
    try do
      DiscordNotifier.send_enriched_kill_embed(killmail, killmail.killmail_id)
      :ok
    rescue
      e ->
        AppLogger.kill_error("Error sending notification: #{Exception.message(e)}")
        {:error, :notification_error}
    end
  end

  def notify(other) do
    AppLogger.kill_error("Cannot send notification for non-KillmailData: #{inspect(other)}")
    {:error, :invalid_data_type}
  end

  # Helper to format a summary of the killmail for logging/debugging
  defp format_summary(killmail) do
    "Kill ##{killmail.killmail_id}: #{killmail.victim_name} (#{killmail.victim_ship_name}) in #{killmail.solar_system_name}"
  end
end
