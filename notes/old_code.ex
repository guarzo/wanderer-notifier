defmodule WandererNotifier.Service.KillProcessor do
  @moduledoc """
  Handles kill messages from zKill, including enrichment and deciding
  whether to send a Discord notification.
  Only notifies if the kill is from a tracked system or involves a tracked character.
  """
  require Logger
  alias WandererNotifier.ZKill.Service, as: ZKillService
  alias WandererNotifier.NotifierFactory
  alias WandererNotifier.Config
  alias WandererNotifier.Features
  alias WandererNotifier.Helpers.CacheHelpers

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

    # Store this kill in our recent kills list regardless of whether we'll notify about it
    if kill_id do
      store_recent_kill(decoded_message)
      Logger.debug("Stored kill_id=#{kill_id} in recent kills list (#{length(Process.get(@recent_kills_key, []))} kills stored)")
    end

    # First check if kill notifications are enabled
    if not Features.kill_notifications_enabled?() do
      Logger.debug("NOTIFICATION DECISION: Kill notifications are disabled, ignoring kill #{kill_id}")
      state
    else
      # Check if system is tracked
      is_tracked_system = kill_in_tracked_system?(system_id)
      Logger.debug("TRACKING CHECK: System #{system_id} is #{if is_tracked_system, do: "tracked", else: "not tracked"}")

      # Check if kill includes tracked character
      has_tracked_character = kill_includes_tracked_character?(decoded_message)
      Logger.debug("TRACKING CHECK: Kill #{kill_id} #{if has_tracked_character, do: "includes", else: "does not include"} tracked character")

      # Determine if we should process this kill
      should_process_system = is_tracked_system
      should_process_character = has_tracked_character

      cond do
        # If the kill is in a tracked system
        should_process_system ->
          case get_enriched_killmail(kill_id) do
            {:ok, []} ->
              # If enrichment fails, try using the raw message
              Logger.warning("Enrichment returned empty result for kill_id=#{kill_id}, falling back to raw message")
              # Try to enrich the raw message with system name
              enriched_message = enrich_with_system_name(decoded_message)
              process_kill(kill_id, state, enriched_message)

            {:ok, enriched_kill} ->
              Logger.info("Successfully enriched kill_id=#{kill_id}")
              # Ensure system name is included
              enriched_kill = ensure_system_name(enriched_kill)
              process_kill(kill_id, state, enriched_kill)

            {:error, reason} ->
              Logger.error("Failed to get enriched killmail for #{kill_id}: #{inspect(reason)}")
              state
          end

        # If the kill includes a tracked character
        should_process_character ->
          case get_enriched_killmail(kill_id) do
            {:ok, enriched_kill} ->
              Logger.info("Successfully enriched kill_id=#{kill_id}")
              # Ensure system name is included
              enriched_kill = ensure_system_name(enriched_kill)
              process_kill(kill_id, state, enriched_kill)
            {:error, reason} ->
              Logger.error("Failed to get enriched killmail for #{kill_id}: #{inspect(reason)}")
              # Try to enrich the raw message with system name
              enriched_message = enrich_with_system_name(decoded_message)
              process_kill(kill_id, state, enriched_message)
          end

        # Otherwise, ignore the kill
        true ->
          Logger.debug("NOTIFICATION DECISION: Kill #{kill_id} ignored (not from tracked system or involving tracked character)")
          state
      end
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

  defp process_kill(kill_id, state, enriched_kill) do
    # Get the processed_kill_ids map from state, defaulting to an empty map if not present
    processed_kill_ids = Map.get(state, :processed_kill_ids, %{})

    if Map.has_key?(processed_kill_ids, kill_id) do
      Logger.debug("Kill mail #{kill_id} already processed, skipping.")
      state
    else
      do_enrich_and_notify(kill_id, enriched_kill)

      # Update the processed_kill_ids map, handling both map and empty state cases
      processed_kill_ids = Map.put(processed_kill_ids, kill_id, :os.system_time(:second))
      Map.put(state, :processed_kill_ids, processed_kill_ids)
    end
  end

  defp do_enrich_and_notify(kill_id, enriched_kill) do
    Logger.debug("Starting notification process for kill_id=#{kill_id}")

    # Log key information about the kill
    victim_name = get_in(enriched_kill, ["victim", "character_name"]) || "Unknown"
    victim_ship = get_in(enriched_kill, ["victim", "ship_type_name"]) || "Unknown Ship"
    system_name = get_in(enriched_kill, ["solar_system_name"]) || "Unknown System"

    # Count attackers
    attackers_count = length(Map.get(enriched_kill, "attackers", []))

    Logger.info("NOTIFICATION DETAILS: #{victim_name} lost a #{victim_ship} in #{system_name} (#{attackers_count} attackers)")

    # Send the notification using our improved notify_kill function
    Logger.debug("Sending Discord notification for kill_id=#{kill_id}")
    notify_kill(enriched_kill, kill_id)
    Logger.debug("Successfully sent Discord notification for kill_id=#{kill_id}")
  end

  defp kill_in_tracked_system?(system_id) do
    # Get tracked systems from the map API
    tracked_systems = CacheHelpers.get_tracked_systems()
    tracked_ids = Enum.map(tracked_systems, fn s ->
      # Handle both string and atom keys
      system_id = Map.get(s, "system_id") || Map.get(s, :system_id) || ""
      to_string(system_id)
    end)
    system_id_str = to_string(system_id)

    # Check if the system is in the tracked systems list
    is_tracked = system_id_str in tracked_ids

    if is_tracked do
      Logger.debug("Kill is in tracked system: #{system_id_str}")
      true
    else
      Logger.debug("Kill is not in tracked system: #{system_id_str}")
      false
    end
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

  # Helper function to enrich a kill with all necessary data
  defp fully_enrich_kill(kill) do
    # Convert the kill to a map if it's not already
    kill = if is_map(kill) do
      kill
    else
      Map.new(kill)
    end

    # Extract ESI data if it exists
    esi_data = Map.get(kill, :esi_data) || Map.get(kill, "esi_data")

    # Merge ESI data into the kill if it exists
    kill = if esi_data do
      Map.merge(kill, esi_data)
    else
      kill
    end

    # Add solar system name
    kill = enrich_with_system_name(kill)

    # Enrich victim data
    victim = Map.get(kill, "victim") || Map.get(kill, :victim) || %{}
    enriched_victim = enrich_entity(victim)
    kill = Map.put(kill, "victim", enriched_victim)

    # Enrich attackers data
    attackers = Map.get(kill, "attackers") || Map.get(kill, :attackers) || []
    enriched_attackers = Enum.map(attackers, &enrich_entity/1)
    kill = Map.put(kill, "attackers", enriched_attackers)

    kill
  end

  # Helper function to enrich an entity (victim or attacker) with character, corporation, and ship info
  defp enrich_entity(entity) do
    # Get character name
    character_id = Map.get(entity, "character_id") || Map.get(entity, :character_id)

    entity = if character_id do
      case WandererNotifier.ESI.Service.get_character_info(character_id) do
        {:ok, char_data} ->
          char_name = Map.get(char_data, "name", "Unknown Pilot")
          Map.put(entity, "character_name", char_name)
        error ->
          Logger.debug("Failed to get character info: #{inspect(error)}")
          Map.put_new(entity, "character_name", "Unknown Pilot")
      end
    else
      Map.put_new(entity, "character_name", "Unknown Pilot")
    end

    # Get corporation name
    corporation_id = Map.get(entity, "corporation_id") || Map.get(entity, :corporation_id)

    entity = if corporation_id do
      case WandererNotifier.ESI.Service.get_corporation_info(corporation_id) do
        {:ok, corp_data} ->
          corp_name = Map.get(corp_data, "name", "Unknown Corp")
          Map.put(entity, "corporation_name", corp_name)
        error ->
          Logger.debug("Failed to get corporation info: #{inspect(error)}")
          Map.put_new(entity, "corporation_name", "Unknown Corp")
      end
    else
      Map.put_new(entity, "corporation_name", "Unknown Corp")
    end

    # Get ship type name
    ship_type_id = Map.get(entity, "ship_type_id") || Map.get(entity, :ship_type_id)

    entity = if ship_type_id do
      case WandererNotifier.ESI.Service.get_ship_type_name(ship_type_id) do
        {:ok, ship_data} ->
          ship_name = Map.get(ship_data, "name", "Unknown Ship")
          Map.put(entity, "ship_type_name", ship_name)
        error ->
          Logger.debug("Failed to get ship type: #{inspect(error)}")
          Map.put_new(entity, "ship_type_name", "Unknown Ship")
      end
    else
      Map.put_new(entity, "ship_type_name", "Unknown Ship")
    end

    entity
  end

  defp get_enriched_killmail(kill_id) do
    case ZKillService.get_enriched_killmail(kill_id) do
      {:ok, enriched_kill} ->
        # Fully enrich the kill with all necessary data
        enriched_kill = fully_enrich_kill(enriched_kill)
        Logger.debug("Successfully enriched kill_id=#{kill_id}")
        {:ok, enriched_kill}
      {:error, err} ->
        {:error, err}
    end
  end

  defp notify_kill(kill_data, kill_id) do
    # Add more detailed logging about the kill being notified
    Logger.info("SENDING NOTIFICATION for kill_id=#{kill_id}")

    # Log some basic details about the kill
    victim_name = get_in(kill_data, ["victim", "character_name"]) || get_in(kill_data, [:victim, :character_name]) || "Unknown"
    victim_ship = get_in(kill_data, ["victim", "ship_type_name"]) || get_in(kill_data, [:victim, :ship_type_name]) || "Unknown Ship"
    system_name = get_in(kill_data, ["solar_system_name"]) || get_in(kill_data, [:solar_system_name]) || "Unknown System"

    Logger.info("KILL DETAILS: Victim: #{victim_name}, Ship: #{victim_ship}, System: #{system_name}")

    # Send the notification using the correct function
    send_kill_notification(kill_data, kill_id)
  end

  # Send the notification
  defp send_kill_notification(kill_data, kill_id) do
    Logger.info("Sending kill notification for kill ID: #{kill_id}")
    NotifierFactory.notify(:send_enriched_kill_embed, [kill_data, kill_id])
    # Increment the kill counter
    WandererNotifier.Stats.increment(:kills)
  end

  @doc """
  Manually triggers a test kill notification using a real kill from zKillboard.
  This is useful for testing Discord notifications.
  """
  def send_test_kill_notification do
    Logger.info("TEST NOTIFICATION: Manually triggering a test kill notification")

    # Try to get a real kill from zKillboard
    case WandererNotifier.ZKill.Service.get_recent_kills(20) do
      {:ok, kills} when is_list(kills) and length(kills) > 0 ->
        # Find a kill with a valid kill_id
        kill_with_id = Enum.find(kills, fn kill ->
          kill_id = Map.get(kill, "killmail_id") || Map.get(kill, :killmail_id)
          kill_id != nil
        end)

        case kill_with_id do
          nil ->
            Logger.error("TEST NOTIFICATION: No kills with valid IDs found")
            fallback_to_recent_kills()

          kill ->
            kill_id = Map.get(kill, "killmail_id") || Map.get(kill, :killmail_id)
            Logger.debug("TEST NOTIFICATION: Using real kill_id=#{kill_id} from zKillboard API")

            # Get the hash from the zkb data
            zkb_data = Map.get(kill, "zkb")
            hash = if zkb_data, do: Map.get(zkb_data, "hash"), else: nil

            if hash do
              # Directly fetch the ESI data for this kill
              case WandererNotifier.ESI.Service.get_esi_kill_mail(kill_id, hash) do
                {:ok, esi_data} ->
                  # Combine the zkb and ESI data
                  enriched_kill = Map.merge(kill, esi_data)

                  # Use the shared enrichment function
                  enriched_kill = fully_enrich_kill(enriched_kill)

                  Logger.debug("TEST NOTIFICATION: Successfully enriched kill_id=#{kill_id}")
                  Logger.debug("TEST NOTIFICATION: Kill data: #{inspect(enriched_kill, pretty: true, limit: 10000)}")

                  # Send the notification directly
                  Logger.debug("TEST NOTIFICATION: Sending Discord notification for test kill")
                  notify_kill(enriched_kill, kill_id)
                  Logger.info("TEST NOTIFICATION: Successfully sent Discord notification for test kill")

                  # Store this kill in our recent kills cache
                  recent_kills = Process.get(@recent_kills_key, [])
                  updated_kills = [enriched_kill | recent_kills] |> Enum.take(10)
                  Process.put(@recent_kills_key, updated_kills)

                  {:ok, kill_id}

                {:error, err} ->
                  Logger.error("TEST NOTIFICATION: Failed to get ESI data for kill #{kill_id}: #{inspect(err)}")
                  fallback_to_recent_kills()
              end
            else
              Logger.error("TEST NOTIFICATION: No hash found for kill_id=#{kill_id}")
              fallback_to_recent_kills()
            end
        end

      {:error, _reason} ->
        Logger.error("TEST NOTIFICATION: Failed to fetch kills from zKillboard API")
        fallback_to_recent_kills()

      _ ->
        Logger.error("TEST NOTIFICATION: No kills returned from zKillboard API")
        fallback_to_recent_kills()
    end
  end

  # Fallback to using recent kills from memory or creating a mock kill as last resort
  defp fallback_to_recent_kills do
    # Get the most recent kill from our stored list
    recent_kills = Process.get(@recent_kills_key, [])
    Logger.debug("TEST NOTIFICATION: Falling back to #{length(recent_kills)} recent kills in memory")

    case get_most_recent_kill() do
      nil ->
        Logger.error("TEST NOTIFICATION: No recent kills available, cannot create test notification")
        {:error, :no_kills_available}

      kill ->
        kill_id = Map.get(kill, "killmail_id") || Map.get(kill, :killmail_id)

        if kill_id do
          Logger.debug("TEST NOTIFICATION: Using kill_id=#{kill_id} from memory for test notification")

          # Send the notification directly
          Logger.debug("TEST NOTIFICATION: Sending Discord notification for test kill")
          notify_kill(kill, kill_id)
          Logger.info("TEST NOTIFICATION: Successfully sent Discord notification for test kill")

          {:ok, kill_id}
        else
          Logger.error("TEST NOTIFICATION: No kill_id found in recent kill data")
          {:error, :no_kill_id}
        end
    end
  end

  # Get the most recent kills
  def get_recent_kills do
    recent_kills = Process.get(@recent_kills_key, [])
    Logger.info("Returning #{length(recent_kills)} recent kills")
    recent_kills
  end

  # Helper function to ensure system name is included in the kill data
  defp ensure_system_name(kill_data) do
    enrich_with_system_name(kill_data)
  end

  # Helper function to enrich raw message with system name
  defp enrich_with_system_name(message) do
    system_name = get_in(message, ["solar_system_name"]) || get_in(message, [:solar_system_name])

    if system_name do
      # System name already exists
      message
    else
      system_id = Map.get(message, "solar_system_id") || Map.get(message, :solar_system_id)

      if system_id do
        case WandererNotifier.ESI.Service.get_solar_system_name(system_id) do
          {:ok, system_data} ->
            system_name = Map.get(system_data, "name", "Unknown System")
            Map.put(message, "solar_system_name", system_name)
          error ->
            Logger.debug("Failed to get system name: #{inspect(error)}")
            # If ESI lookup fails, use a default name
            Map.put(message, "solar_system_name", "Unknown System")
        end
      else
        # If no system ID, use a default name
        Map.put(message, "solar_system_name", "Unknown System")
      end
    end
  end
end
