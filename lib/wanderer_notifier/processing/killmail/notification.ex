defmodule WandererNotifier.Processing.Killmail.Notification do
  @moduledoc """
  Specialized module for processing kill notifications.
  Encapsulates all the notification handling logic for kills.
  """

  alias WandererNotifier.Core.Stats
  alias WandererNotifier.Data.Cache.Repository, as: CacheRepo
  alias WandererNotifier.Discord.Notifier, as: DiscordNotifier
  alias WandererNotifier.Logger.Logger, as: AppLogger
  alias WandererNotifier.Notifiers.Determiner
  alias WandererNotifier.Processing.Killmail.Enrichment

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
    # Delegate to the Determiner module for notification logic
    Determiner.should_notify_kill?(killmail, system_id)
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
      case Determiner.check_deduplication(:kill, kill_id) do
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
    recent_kills = CacheRepo.get_recent_kills()
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
      # Get the first kill
      recent_kill = List.first(recent_kills)

      # Extract kill_id regardless of struct type
      kill_id = extract_kill_id(recent_kill)

      # Log what we're using for testing
      AppLogger.kill_debug("Using kill data for test notification with kill_id: #{kill_id}")

      # Create a Data.Killmail struct if needed
      killmail = ensure_data_killmail(recent_kill)

      # Make sure to enrich the killmail data before sending notification
      # This will try to get real data from APIs first
      enriched_kill = Enrichment.enrich_killmail_data(killmail)

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

  # Helper to extract kill_id regardless of struct type
  defp extract_kill_id(kill) do
    cond do
      is_struct(kill, WandererNotifier.Data.Killmail) -> kill.killmail_id
      is_struct(kill, WandererNotifier.Resources.Killmail) -> kill.killmail_id
      is_map(kill) -> Map.get(kill, "killmail_id") || Map.get(kill, :killmail_id)
      true -> nil
    end
  end

  # Helper to ensure we have a Data.Killmail struct
  defp ensure_data_killmail(kill) do
    cond do
      is_struct(kill, WandererNotifier.Data.Killmail) ->
        # Already the right type
        kill

      is_struct(kill, WandererNotifier.Resources.Killmail) ->
        # Convert from Resources.Killmail to Data.Killmail
        WandererNotifier.Data.Killmail.new(
          kill.killmail_id,
          Map.get(kill, :zkb_data) || %{}
        )

      is_map(kill) ->
        # Convert from map to Data.Killmail
        WandererNotifier.Data.Killmail.new(
          Map.get(kill, "killmail_id") || Map.get(kill, :killmail_id),
          Map.get(kill, "zkb") || Map.get(kill, :zkb) || %{}
        )

      true ->
        # Default empty killmail as fallback
        WandererNotifier.Data.Killmail.new(nil, %{})
    end
  end

  # Validate killmail has all required data for notification
  defp validate_killmail_data(killmail) do
    # For Data.Killmail struct
    if is_struct(killmail, WandererNotifier.Data.Killmail) do
      # Check victim data
      victim = Map.get(killmail, :victim) || %{}

      # Check system name
      esi_data = Map.get(killmail, :esi_data) || %{}
      system_name = Map.get(esi_data, "solar_system_name")

      validate_fields(victim, system_name)
    else
      # Fall back to treating it as a generic map
      victim = Map.get(killmail, :victim_data) || %{}
      system_name = Map.get(killmail, :solar_system_name)

      validate_fields(victim, system_name)
    end
  end

  # Validate the required fields
  defp validate_fields(victim, system_name) do
    cond do
      victim == nil || victim == %{} ->
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
