defmodule WandererNotifier.Processing.Killmail.Notification do
  @moduledoc """
  Specialized module for processing kill notifications.
  Encapsulates all the notification handling logic for kills.
  """

  alias WandererNotifier.Core.Stats
  alias WandererNotifier.Data.Cache.Keys, as: CacheKeys
  alias WandererNotifier.Data.Cache.Repository, as: CacheRepo
  alias WandererNotifier.Logger.Logger, as: AppLogger
  alias WandererNotifier.Notifications.Determiner.Kill, as: KillDeterminer
  alias WandererNotifier.Notifiers.Factory, as: NotifierFactory
  alias WandererNotifier.Notifiers.StructuredFormatter
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
  def should_notify_kill?(killmail, _system_id \\ nil) do
    # Delegate to the KillDeterminer module for notification logic
    KillDeterminer.should_notify?(killmail)
  end

  @doc """
  Sends a kill notification.
  """
  def send_kill_notification(enriched_killmail, kill_id, _bypass_dedup \\ false) do
    AppLogger.kill_info("Sending kill notification", %{kill_id: kill_id})

    # Check if the kill is relevant for system and/or character channels
    has_tracked_system = KillDeterminer.tracked_in_system?(enriched_killmail)
    tracked_characters = KillDeterminer.get_tracked_characters(enriched_killmail)
    has_tracked_characters = length(tracked_characters) > 0

    # Log what was detected
    log_notification_relevance(
      kill_id,
      has_tracked_system,
      has_tracked_characters,
      tracked_characters
    )

    # Send notifications to appropriate channels
    system_result = process_system_notification(enriched_killmail, kill_id, has_tracked_system)

    character_result =
      process_character_notification(
        enriched_killmail,
        kill_id,
        has_tracked_characters,
        tracked_characters
      )

    # Return combined result
    combine_notification_results(system_result, character_result, kill_id)
  end

  # Log relevance information for debugging
  defp log_notification_relevance(
         kill_id,
         has_tracked_system,
         has_tracked_characters,
         tracked_characters
       ) do
    AppLogger.kill_debug("Notification relevance", %{
      kill_id: kill_id,
      has_tracked_system: has_tracked_system,
      has_tracked_characters: has_tracked_characters,
      num_tracked_characters: length(tracked_characters)
    })
  end

  # Process system notification if needed
  defp process_system_notification(enriched_killmail, kill_id, has_tracked_system) do
    if has_tracked_system do
      # Prepare system notification
      system_generic_notification =
        StructuredFormatter.format_kill_notification(enriched_killmail)

      system_discord_format = StructuredFormatter.to_discord_format(system_generic_notification)

      # Send system notification
      send_system_notification(system_discord_format, kill_id)
    else
      {:ok, :skipped_system}
    end
  end

  # Process character notification if needed
  defp process_character_notification(
         enriched_killmail,
         kill_id,
         has_tracked_characters,
         tracked_characters
       ) do
    if has_tracked_characters do
      # Determine if tracked characters are victims or attackers
      are_victims =
        KillDeterminer.are_tracked_characters_victims?(enriched_killmail, tracked_characters)

      # Prepare character notification with appropriate color
      character_generic_notification =
        StructuredFormatter.format_character_kill_notification(
          enriched_killmail,
          tracked_characters,
          are_victims
        )

      character_discord_format =
        StructuredFormatter.to_discord_format(character_generic_notification)

      # Send character notification
      send_character_notification(character_discord_format, kill_id)
    else
      {:ok, :skipped_character}
    end
  end

  # Send system notification and handle result
  defp send_system_notification(discord_format, kill_id) do
    case NotifierFactory.notify(:send_system_kill_discord_embed, [discord_format]) do
      :ok ->
        AppLogger.kill_info("System kill notification sent successfully", %{kill_id: kill_id})
        # Increment both notifications.kills and processing.kills_notified
        Stats.increment(:kills)
        Stats.increment(:kill_notified)
        {:ok, kill_id}

      {:ok, _} ->
        AppLogger.kill_info("System kill notification sent successfully", %{kill_id: kill_id})
        # Increment both notifications.kills and processing.kills_notified
        Stats.increment(:kills)
        Stats.increment(:kill_notified)
        {:ok, kill_id}

      {:error, reason} ->
        AppLogger.kill_error("Failed to send system kill notification", %{
          kill_id: kill_id,
          error: inspect(reason)
        })

        {:error, reason}
    end
  end

  # Send character notification and handle result
  defp send_character_notification(discord_format, kill_id) do
    case NotifierFactory.notify(:send_character_kill_discord_embed, [discord_format]) do
      :ok ->
        AppLogger.kill_info("Character kill notification sent successfully", %{kill_id: kill_id})
        # Increment both notifications.kills and processing.kills_notified
        Stats.increment(:kills)
        Stats.increment(:kill_notified)
        {:ok, kill_id}

      {:ok, _} ->
        AppLogger.kill_info("Character kill notification sent successfully", %{kill_id: kill_id})
        # Increment both notifications.kills and processing.kills_notified
        Stats.increment(:kills)
        Stats.increment(:kill_notified)
        {:ok, kill_id}

      {:error, reason} ->
        AppLogger.kill_error("Failed to send character kill notification", %{
          kill_id: kill_id,
          error: inspect(reason)
        })

        {:error, reason}
    end
  end

  # Combine notification results and return appropriate response
  defp combine_notification_results(system_result, character_result, kill_id) do
    case {system_result, character_result} do
      {{:ok, _}, {:ok, _}} ->
        # Both succeeded or were skipped
        {:ok, kill_id}

      {{:error, reason}, _} ->
        # System notification failed
        {:error, reason}

      {_, {:error, reason}} ->
        # Character notification failed
        {:error, reason}
    end
  end

  @doc """
  Sends a test kill notification using recent data.
  """
  def send_test do
    AppLogger.kill_info("Sending test kill notification...")

    # Get recent kills using proper cache key
    recent_kills = CacheRepo.get(CacheKeys.zkill_recent_kills())
    AppLogger.kill_debug("Found #{length(recent_kills)} recent kills in shared cache repository")

    if recent_kills == [] do
      error_message = "No recent kills available for test notification"
      AppLogger.kill_error(error_message)

      # Notify the user through Discord
      NotifierFactory.notify(:send_message, [
        "Error: #{error_message} - No test notification sent. Please wait for some kills to be processed."
      ])

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
          NotifierFactory.notify(:send_message, [error_message])

          {:error, error_message}
      end
    end
  end

  # Helper to extract kill_id regardless of struct type
  defp extract_kill_id(kill) do
    if is_struct(kill, WandererNotifier.Resources.Killmail) do
      kill.killmail_id
    else
      nil
    end
  end

  # Helper to ensure we have a proper killmail format
  defp ensure_data_killmail(kill) do
    if is_struct(kill, WandererNotifier.Resources.Killmail) do
      # Return the normalized killmail resource
      kill
    else
      # If not a proper killmail resource, return nil to indicate invalid input
      nil
    end
  end

  # Validate killmail has all required data for notification
  defp validate_killmail_data(killmail) do
    if is_struct(killmail, WandererNotifier.Resources.Killmail) do
      # For normalized Resource.Killmail
      victim_name = killmail.victim_name
      ship_type_name = killmail.victim_ship_name
      system_name = killmail.solar_system_name

      cond do
        is_nil(victim_name) || victim_name == "" ->
          {:error, "Killmail is missing victim name"}

        is_nil(ship_type_name) || ship_type_name == "" ->
          {:error, "Victim is missing ship type name"}

        is_nil(system_name) || system_name == "" ->
          {:error, "Killmail is missing system name"}

        true ->
          :ok
      end
    else
      # Invalid input, not a normalized resource
      {:error, "Input is not a valid Killmail resource"}
    end
  end
end
