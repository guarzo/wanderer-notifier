defmodule WandererNotifier.Service.KillProcessor do
  @moduledoc """
  Handles kill messages from zKill, including enrichment and deciding
  whether to send a Discord notification.
  Only notifies if the kill is from a tracked system or involves a tracked character.
  """
  require Logger
  alias WandererNotifier.ZKill.Service, as: ZKillService
  alias WandererNotifier.Discord.Notifier
  alias WandererNotifier.Config
  alias WandererNotifier.Features
  alias WandererNotifier.Helpers.CacheHelpers

  # Time between forced kill notifications (5 minutes)
  @forced_notification_interval :timer.minutes(5)

  # Process dictionary key for last forced notification time
  @last_forced_notification_key :last_forced_kill_notification

  # Process dictionary key for recent kills
  @recent_kills_key :recent_kills

  # Maximum number of recent kills to store
  @max_recent_kills 10

  def process_zkill_message(message, state) when is_binary(message) do
    case Jason.decode(message) do
      {:ok, decoded} -> process_decoded_message(decoded, state)
      {:error, error} ->
        Logger.error("Failed to decode zkill message: #{inspect(error)}")
        state
    end
  end

  def process_zkill_message(message, state) when is_map(message) do
    process_decoded_message(message, state)
  end

  defp process_decoded_message(decoded_message, state) do
    kill_id = Map.get(decoded_message, "killmail_id")
    system_id = Map.get(decoded_message, "solar_system_id")

    # Log the incoming kill data
    Logger.debug("Processing kill_id=#{kill_id} in system_id=#{system_id}")

    # Store this kill in our recent kills list
    if kill_id do
      store_recent_kill(decoded_message)
      Logger.debug("Stored kill_id=#{kill_id} in recent kills list (#{length(Process.get(@recent_kills_key, []))} kills stored)")
    end

    # Check if we should force a notification regardless of filters
    should_force_notification = should_force_notification?()

    if should_force_notification do
      Logger.info("FORCE NOTIFICATION: 5-minute interval reached, forcing notification for kill_id=#{kill_id}")
    end

    cond do
      # If we should force a notification, do it
      should_force_notification ->
        Logger.info("Forcing kill notification for kill_id=#{kill_id} (5-minute interval)")
        case get_enriched_killmail(kill_id) do
          {:ok, enriched_kill} ->
            Logger.info("Successfully enriched kill_id=#{kill_id} for forced notification")
            notify_kill(enriched_kill, kill_id)
            # Update the last forced notification time
            Process.put(@last_forced_notification_key, :os.system_time(:second))
            Logger.info("Updated last forced notification time to #{:os.system_time(:second)}")
            state
          {:error, reason} ->
            Logger.error("Failed to get enriched killmail for forced notification #{kill_id}: #{inspect(reason)}")
            state
        end

      # Otherwise, use normal filtering logic
      kill_in_tracked_system?(system_id) ->
        Logger.info("NOTIFICATION REASON: Kill is in a tracked system")
        case get_enriched_killmail(kill_id) do
          {:ok, []} ->
            # If enrichment fails, try using the raw message
            Logger.warning("Enrichment returned empty result for kill_id=#{kill_id}, falling back to raw message")
            if kill_includes_tracked_character?(decoded_message) do
              Logger.info("Raw message includes tracked character, proceeding with notification")
              notify_kill(decoded_message, kill_id)
            else
              Logger.info("Raw message does not include tracked character, skipping notification")
            end
            state

          {:ok, enriched_kill} ->
            Logger.info("Successfully enriched kill_id=#{kill_id}")
            if kill_includes_tracked_character?(enriched_kill) do
              Logger.info("Enriched kill includes tracked character, proceeding with notification")
              notify_kill(enriched_kill, kill_id)
            else
              Logger.info("Enriched kill does not include tracked character, but system is tracked")
              notify_kill(enriched_kill, kill_id)
            end
            state

          {:error, reason} ->
            Logger.error("Failed to get enriched killmail for #{kill_id}: #{inspect(reason)}")
            state
        end

      true ->
        Logger.debug("Kill_id=#{kill_id} is not in a tracked system and force notification is not triggered")
        state
    end
  end

  # Store a kill in the recent kills list
  defp store_recent_kill(kill) do
    recent_kills = Process.get(@recent_kills_key, [])

    # Add the new kill to the front of the list
    updated_kills = [kill | recent_kills]

    # Keep only the most recent @max_recent_kills
    updated_kills = Enum.take(updated_kills, @max_recent_kills)

    # Store the updated list
    Process.put(@recent_kills_key, updated_kills)
  end

  # Get the most recent kill
  defp get_most_recent_kill do
    recent_kills = Process.get(@recent_kills_key, [])
    List.first(recent_kills)
  end

  # Check if we should force a notification based on time elapsed
  defp should_force_notification?() do
    last_time = Process.get(@last_forced_notification_key, 0)
    current_time = :os.system_time(:second)
    elapsed_seconds = current_time - last_time

    # Convert @forced_notification_interval from milliseconds to seconds for comparison
    interval_seconds = div(@forced_notification_interval, 1000)

    elapsed_seconds >= interval_seconds
  end

  defp process_kill(kill_id, state) do
    # Get the processed_kill_ids map from state, defaulting to an empty map if not present
    processed_kill_ids = Map.get(state, :processed_kill_ids, %{})

    if Map.has_key?(processed_kill_ids, kill_id) do
      Logger.info("Kill mail #{kill_id} already processed, skipping.")
      state
    else
      do_enrich_and_notify(kill_id)

      # Update the processed_kill_ids map, handling both map and empty state cases
      processed_kill_ids = Map.put(processed_kill_ids, kill_id, :os.system_time(:second))
      Map.put(state, :processed_kill_ids, processed_kill_ids)
    end
  end

  defp do_enrich_and_notify(kill_id) do
    Logger.info("Starting enrichment and notification process for kill_id=#{kill_id}")

    case ZKillService.get_enriched_killmail(kill_id) do
      {:ok, enriched_kill} ->
        # Log key information about the kill
        victim_name = get_in(enriched_kill, ["victim", "character_name"]) || "Unknown"
        victim_ship = get_in(enriched_kill, ["victim", "ship_type_name"]) || "Unknown Ship"
        system_name = get_in(enriched_kill, ["solar_system_name"]) || "Unknown System"

        # Count attackers
        attackers_count = length(Map.get(enriched_kill, "attackers", []))

        Logger.info("NOTIFICATION DETAILS: #{victim_name} lost a #{victim_ship} in #{system_name} (#{attackers_count} attackers)")
        Logger.debug("Enriched killmail for kill #{kill_id}: #{inspect(enriched_kill, limit: 5000)}")

        # Send the notification
        Logger.info("Sending Discord notification for kill_id=#{kill_id}")
        Notifier.send_enriched_kill_embed(enriched_kill, kill_id)
        Logger.info("Successfully sent Discord notification for kill_id=#{kill_id}")

      {:error, err} ->
        error_msg = "Failed to process kill #{kill_id}: #{inspect(err)}"
        Logger.error(error_msg)
        # Only log the error, don't send Discord notifications for processing errors
    end
  end

  defp kill_in_tracked_system?(system_id) do
    tracked_systems = CacheHelpers.get_tracked_systems()
    tracked_ids = Enum.map(tracked_systems, fn s ->
      # Handle both string and atom keys
      system_id = s["system_id"] || s[:system_id] || ""
      to_string(system_id)
    end)
    system_id_str = to_string(system_id)

    is_tracked = system_id_str in tracked_ids

    if is_tracked do
      Logger.debug("Kill is in tracked system: #{system_id_str}")
    else
      Logger.debug("Kill is not in tracked system: #{system_id_str}")
    end

    is_tracked
  end

  defp kill_includes_tracked_character?(kill_data) do
    tracked_characters = Config.tracked_characters()
    tracked_chars = Enum.map(tracked_characters, &to_string/1)

    # Log the tracked characters for debugging
    Logger.debug("Checking kill against #{length(tracked_chars)} tracked characters: #{inspect(tracked_chars)}")

    # Get victim ID safely
    victim = Map.get(kill_data, "victim", %{})
    victim_id = Map.get(victim, "character_id")
    victim_id_str = if victim_id, do: to_string(victim_id), else: nil

    # Check if victim is tracked
    victim_tracked = victim_id_str && victim_id_str in tracked_chars
    if victim_tracked do
      victim_name = Map.get(victim, "character_name", "Unknown")
      Logger.info("CHARACTER MATCH: Victim #{victim_name} (ID: #{victim_id_str}) is in tracked characters list")
    end

    # Get attacker IDs safely
    attackers = Map.get(kill_data, "attackers", [])

    # Check each attacker and log if they're tracked
    tracked_attackers = Enum.filter(attackers, fn attacker ->
      attacker_id = Map.get(attacker, "character_id")
      attacker_id_str = if attacker_id, do: to_string(attacker_id), else: nil
      is_tracked = attacker_id_str && attacker_id_str in tracked_chars

      if is_tracked do
        attacker_name = Map.get(attacker, "character_name", "Unknown")
        Logger.info("CHARACTER MATCH: Attacker #{attacker_name} (ID: #{attacker_id_str}) is in tracked characters list")
      end

      is_tracked
    end)

    # Return true if either victim or any attacker is tracked
    victim_tracked || length(tracked_attackers) > 0
  end

  defp get_enriched_killmail(kill_id) do
    case ZKillService.get_enriched_killmail(kill_id) do
      {:ok, enriched_kill} ->
        {:ok, enriched_kill}
      {:error, err} ->
        {:error, err}
    end
  end

  defp notify_kill(_kill_data, kill_id) do
    Logger.info("Evaluating notification criteria for kill_id=#{kill_id}")

    # Check if system notifications are enabled
    systems_enabled = Features.enabled?(:tracked_systems_notifications)
    Logger.info("Feature status: tracked_systems_notifications=#{systems_enabled}")

    # Check if character tracking notifications are enabled
    # We've modified the Features module to allow this even without a license
    if Features.enabled?(:tracked_characters_notifications) do
      Logger.debug("Character tracking notifications are enabled, checking if kill involves tracked character")

      # Get the enriched killmail
      case get_enriched_killmail(kill_id) do
        {:ok, enriched_kill} ->
          if kill_includes_tracked_character?(enriched_kill) do
            Logger.info("NOTIFICATION DECISION: Kill #{kill_id} will be notified (involves tracked character)")
            process_kill(kill_id, %{processed_kill_ids: %{}})
          else
            Logger.info(
              "NOTIFICATION DECISION: Kill #{kill_id} ignored (not from tracked system or involving tracked character)"
            )
            %{processed_kill_ids: %{}}
          end
        {:error, err} ->
          Logger.error("Failed to get enriched killmail for #{kill_id}: #{inspect(err)}")
          %{processed_kill_ids: %{}}
      end
    else
      # This should now rarely happen since we've moved tracked_characters_notifications to core features
      Logger.info("NOTIFICATION DECISION: Kill #{kill_id} ignored (character tracking notifications disabled in configuration)")
      %{processed_kill_ids: %{}}
    end
  end

  @doc """
  Manually triggers a test kill notification using the most recent kill from the websocket.
  This is useful for testing Discord notifications.
  """
  def send_test_kill_notification do
    Logger.info("TEST NOTIFICATION: Manually triggering a test kill notification")

    # Get the most recent kill from our stored list
    recent_kills = Process.get(@recent_kills_key, [])
    Logger.info("TEST NOTIFICATION: Found #{length(recent_kills)} recent kills in memory")

    case get_most_recent_kill() do
      nil ->
        Logger.error("TEST NOTIFICATION: No recent kills available for test notification")
        {:error, :no_kills_available}

      kill ->
        kill_id = Map.get(kill, "killmail_id")
        system_id = Map.get(kill, "solar_system_id")

        if kill_id do
          Logger.info("TEST NOTIFICATION: Using kill_id=#{kill_id} in system_id=#{system_id} for test notification")

          # Log some basic information about the kill
          victim_id = get_in(kill, ["victim", "character_id"])
          victim_name = get_in(kill, ["victim", "character_name"]) || "Unknown"

          Logger.info("TEST NOTIFICATION: Kill details - Victim: #{victim_name} (ID: #{victim_id})")

          # Process the kill through the normal notification path
          # This ensures we use the same logic as real notifications
          Logger.info("TEST NOTIFICATION: Processing kill through normal notification path")
          process_decoded_message(kill, %{processed_kill_ids: %{}})

          Logger.info("TEST NOTIFICATION: Successfully completed test notification process")
          {:ok, kill_id}
        else
          Logger.error("TEST NOTIFICATION: No kill_id found in recent kill data")
          {:error, :no_kill_id}
        end
    end
  end
end
