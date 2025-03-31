defmodule WandererNotifier.Processing.Killmail.Notification do
  @moduledoc """
  Handles killmail notifications.

  - Determines if a kill should trigger a notification
  - Formats the notification content
  - Sends notifications to various channels
  """

  alias WandererNotifier.Core.Logger, as: AppLogger
  alias WandererNotifier.Data.Killmail
  alias WandererNotifier.Discord.Notifier, as: DiscordNotifier
  alias WandererNotifier.Processing.Killmail.{Cache, Enrichment, Stats}
  alias WandererNotifier.Services.NotificationDeterminer

  @doc """
  Determines if a kill notification should be sent and sends it.

  ## Parameters
  - killmail: The killmail struct to process
  - system_id: Optional system ID (will extract from killmail if not provided)

  ## Returns
  - true if a notification was sent
  - false if notification was skipped
  """
  def should_notify_kill?(killmail, system_id \\ nil) do
    # Delegate to the NotificationDeterminer for now
    # In a complete implementation, this logic could be moved here
    NotificationDeterminer.should_notify_kill?(killmail, system_id)
  end

  @doc """
  Send a formatted kill notification.

  ## Parameters
  - enriched_killmail: Enriched killmail struct
  - kill_id: The ID of the kill
  - is_test: Whether this is a test notification (defaults to false)

  ## Returns
  - :ok on success
  - {:error, reason} on failure
  """
  def send_kill_notification(enriched_killmail, kill_id, is_test \\ false) do
    # Add detailed logging for kill notification
    AppLogger.kill_info(
      "📝 NOTIFICATION PREP: Preparing to send notification for killmail #{kill_id}" <>
        if(is_test, do: " (TEST NOTIFICATION)", else: "")
    )

    # For test notifications, bypass deduplication check
    if is_test do
      AppLogger.kill_info(
        "✅ TEST KILL: Sending test notification for killmail #{kill_id}, bypassing deduplication"
      )

      DiscordNotifier.send_enriched_kill_embed(enriched_killmail, kill_id)

      # Update statistics for notification sent
      Stats.update(:notification_sent)

      # Log the notification for tracking purposes
      AppLogger.kill_info(
        "📢 TEST NOTIFICATION SENT: Killmail #{kill_id} test notification delivered successfully"
      )

      :ok
    else
      # Use the centralized deduplication check for normal notifications
      case NotificationDeterminer.check_deduplication(:kill, kill_id) do
        {:ok, :send} ->
          # This is not a duplicate, send the notification
          AppLogger.kill_info("✅ NEW KILL: Sending notification for killmail #{kill_id}")
          DiscordNotifier.send_enriched_kill_embed(enriched_killmail, kill_id)

          # Update statistics for notification sent
          Stats.update(:notification_sent)

          # Log the notification for tracking purposes
          AppLogger.kill_debug(
            "📢 NOTIFICATION SENT: Killmail #{kill_id} notification delivered successfully"
          )

          :ok

        {:ok, :skip} ->
          # This is a duplicate, skip the notification
          AppLogger.kill_info(
            "🔄 DUPLICATE KILL: Killmail #{kill_id} notification already sent, skipping"
          )

          :ok

        {:error, reason} ->
          # Error during deduplication check, log it
          AppLogger.kill_error(
            "⚠️ DEDUPLICATION ERROR: Failed to check killmail #{kill_id}: #{reason}"
          )

          # Default to sending the notification in case of errors
          AppLogger.kill_info("⚠️ FALLBACK: Sending notification despite deduplication error")
          DiscordNotifier.send_enriched_kill_embed(enriched_killmail, kill_id)
          :ok
      end
    end
  end

  @doc """
  Sends a test kill notification using recent data.
  """
  def send_test do
    AppLogger.kill_info("Sending test kill notification...")

    # Get recent kills
    recent_kills = Cache.get_recent_kills()
    AppLogger.kill_debug("Found #{length(recent_kills)} recent kills in shared cache repository")

    if recent_kills == [] do
      error_message = "No recent kills available for test notification"
      AppLogger.kill_error(error_message)

      # Notify the user through Discord
      DiscordNotifier.send_message(
        "Error: #{error_message} - No test notification sent. Please wait for some kills to be processed."
      )

      {:error, error_message}
    else
      # Get the first kill - should already be a Killmail struct
      %Killmail{} = recent_kill = List.first(recent_kills)
      kill_id = recent_kill.killmail_id

      # Log what we're using for testing
      AppLogger.kill_debug("Using kill data for test notification with kill_id: #{kill_id}")

      # Make sure to enrich the killmail data before sending notification
      # This will try to get real data from APIs first
      enriched_kill = Enrichment.enrich_killmail_data(recent_kill)

      # Validate essential data is present - fail if not
      case validate_killmail_data(enriched_kill) do
        :ok ->
          # Use the normal notification flow but bypass deduplication
          AppLogger.kill_info(
            "TEST NOTIFICATION: Using normal notification flow for test kill notification"
          )

          send_kill_notification(enriched_kill, kill_id, true)
          {:ok, kill_id}

        {:error, reason} ->
          # Data validation failed, return error
          error_message = "Cannot send test notification: #{reason}"
          AppLogger.kill_error(error_message)

          # Notify the user through Discord
          DiscordNotifier.send_message(error_message)

          {:error, error_message}
      end
    end
  end

  # Private functions

  # Validate killmail has all required data for notification
  defp validate_killmail_data(%Killmail{} = killmail) do
    # Check victim data
    victim = Killmail.get_victim(killmail)

    # Check system name
    esi_data = killmail.esi_data || %{}
    system_name = Map.get(esi_data, "solar_system_name")

    cond do
      victim == nil ->
        {:error, "Killmail is missing victim data"}

      Map.get(victim, "character_name") == nil ->
        {:error, "Victim is missing character name"}

      Map.get(victim, "ship_type_name") == nil ->
        {:error, "Victim is missing ship type name"}

      system_name == nil ->
        {:error, "Killmail is missing system name"}

      true ->
        :ok
    end
  end
end
