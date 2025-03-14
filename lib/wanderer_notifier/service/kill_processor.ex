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
    Logger.info("Processing kill_id=#{kill_id} in system_id=#{system_id}")

    # Store this kill in our recent kills list
    if kill_id do
      store_recent_kill(decoded_message)
      Logger.debug("Stored kill_id=#{kill_id} in recent kills list (#{length(Process.get(@recent_kills_key, []))} kills stored)")
    end

    # Add debug logging for tracked systems check
    is_tracked_system = kill_in_tracked_system?(system_id)
    Logger.debug("TRACKING CHECK: System #{system_id} is #{if is_tracked_system, do: "tracked", else: "not tracked"}")

    # Add debug logging for tracked characters check
    has_tracked_character = kill_includes_tracked_character?(decoded_message)
    Logger.debug("TRACKING CHECK: Kill #{kill_id} #{if has_tracked_character, do: "includes", else: "does not include"} tracked character")

    # Add debug logging for feature status
    tracked_systems_enabled = Features.tracked_systems_notifications_enabled?()
    tracked_characters_enabled = Features.tracked_characters_notifications_enabled?()
    Logger.debug("FEATURE STATUS: tracked_systems=#{tracked_systems_enabled}, tracked_characters=#{tracked_characters_enabled}")

    cond do
      # If the kill is in a tracked system, process it
      kill_in_tracked_system?(system_id) ->
        Logger.info("NOTIFICATION REASON: Kill is in a tracked system")
        case get_enriched_killmail(kill_id) do
          {:ok, []} ->
            # If enrichment fails, try using the raw message
            Logger.warning("Enrichment returned empty result for kill_id=#{kill_id}, falling back to raw message")
            if kill_includes_tracked_character?(decoded_message) do
              Logger.info("Raw message includes tracked character, proceeding with notification")
              process_kill(kill_id, state, decoded_message)
            else
              Logger.info("Raw message does not include tracked character, skipping notification")
              state
            end

          {:ok, enriched_kill} ->
            Logger.info("Successfully enriched kill_id=#{kill_id}")
            if kill_includes_tracked_character?(enriched_kill) do
              Logger.info("Enriched kill includes tracked character, proceeding with notification")
              process_kill(kill_id, state, enriched_kill)
            else
              Logger.info("Enriched kill does not include tracked character, but system is tracked")
              process_kill(kill_id, state, enriched_kill)
            end

          {:error, reason} ->
            Logger.error("Failed to get enriched killmail for #{kill_id}: #{inspect(reason)}")
            state
        end

      # If the kill includes a tracked character, process it
      kill_includes_tracked_character?(decoded_message) ->
        Logger.info("NOTIFICATION REASON: Kill includes tracked character")
        case get_enriched_killmail(kill_id) do
          {:ok, enriched_kill} ->
            Logger.info("Successfully enriched kill_id=#{kill_id}")
            process_kill(kill_id, state, enriched_kill)
          {:error, reason} ->
            Logger.error("Failed to get enriched killmail for #{kill_id}: #{inspect(reason)}")
            state
        end

      # Otherwise, ignore the kill
      true ->
        Logger.info("NOTIFICATION DECISION: Kill #{kill_id} ignored (not from tracked system or involving tracked character)")
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

  defp process_kill(kill_id, state, enriched_kill) do
    # Get the processed_kill_ids map from state, defaulting to an empty map if not present
    processed_kill_ids = Map.get(state, :processed_kill_ids, %{})

    if Map.has_key?(processed_kill_ids, kill_id) do
      Logger.info("Kill mail #{kill_id} already processed, skipping.")
      state
    else
      do_enrich_and_notify(kill_id, enriched_kill)

      # Update the processed_kill_ids map, handling both map and empty state cases
      processed_kill_ids = Map.put(processed_kill_ids, kill_id, :os.system_time(:second))
      Map.put(state, :processed_kill_ids, processed_kill_ids)
    end
  end

  defp do_enrich_and_notify(kill_id, enriched_kill) do
    Logger.info("Starting notification process for kill_id=#{kill_id}")

    # Log key information about the kill
    victim_name = get_in(enriched_kill, ["victim", "character_name"]) || "Unknown"
    victim_ship = get_in(enriched_kill, ["victim", "ship_type_name"]) || "Unknown Ship"
    system_name = get_in(enriched_kill, ["solar_system_name"]) || "Unknown System"

    # Count attackers
    attackers_count = length(Map.get(enriched_kill, "attackers", []))

    Logger.info("NOTIFICATION DETAILS: #{victim_name} lost a #{victim_ship} in #{system_name} (#{attackers_count} attackers)")
    Logger.debug("Enriched killmail for kill #{kill_id}: #{inspect(enriched_kill, limit: 5000)}")

    # Send the notification using our improved notify_kill function
    Logger.info("Sending Discord notification for kill_id=#{kill_id}")
    notify_kill(enriched_kill, kill_id)
    Logger.info("Successfully sent Discord notification for kill_id=#{kill_id}")
  end

  defp kill_in_tracked_system?(system_id) do
    tracked_systems = CacheHelpers.get_tracked_systems()
    tracked_ids = Enum.map(tracked_systems, fn s ->
      # Handle both string and atom keys
      system_id = Map.get(s, "system_id") || Map.get(s, :system_id) || ""
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

  defp notify_kill(kill_data, kill_id) do
    # Add more detailed logging about the kill being notified
    Logger.info("SENDING NOTIFICATION for kill_id=#{kill_id}")

    # Log some basic details about the kill
    victim_name = get_in(kill_data, ["victim", "character_name"]) || "Unknown"
    victim_ship = get_in(kill_data, ["victim", "ship_type_name"]) || "Unknown Ship"
    system_name = get_in(kill_data, ["solar_system_name"]) || "Unknown System"

    Logger.info("KILL DETAILS: Victim: #{victim_name}, Ship: #{victim_ship}, System: #{system_name}")

    # Send the notification using the correct function
    Notifier.send_enriched_kill_embed(kill_data, kill_id)

    # Update stats with the correct function
    WandererNotifier.Stats.increment(:kills)
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
        Logger.info("TEST NOTIFICATION: No recent kills available, creating a mock kill for testing")

        # Create a mock kill with basic data
        mock_kill = create_mock_kill()
        kill_id = Map.get(mock_kill, "killmail_id")
        system_id = Map.get(mock_kill, "solar_system_id")

        Logger.info("TEST NOTIFICATION: Created mock kill_id=#{kill_id} in system_id=#{system_id} for test notification")

        # Log some basic information about the mock kill
        victim_name = get_in(mock_kill, ["victim", "character_name"])
        victim_ship = get_in(mock_kill, ["victim", "ship_type_name"])

        Logger.info("TEST NOTIFICATION: Mock kill details - Victim: #{victim_name} lost a #{victim_ship}")

        # Send the notification directly
        Logger.info("TEST NOTIFICATION: Sending Discord notification for mock test kill")
        notify_kill(mock_kill, kill_id)
        Logger.info("TEST NOTIFICATION: Successfully sent Discord notification for mock test kill")

        {:ok, kill_id}

      kill ->
        kill_id = Map.get(kill, "killmail_id")
        system_id = Map.get(kill, "solar_system_id")

        if kill_id do
          Logger.info("TEST NOTIFICATION: Using kill_id=#{kill_id} in system_id=#{system_id} for test notification")

          # Log some basic information about the kill
          victim_id = get_in(kill, ["victim", "character_id"])
          victim_name = get_in(kill, ["victim", "character_name"]) || "Unknown"

          Logger.info("TEST NOTIFICATION: Kill details - Victim: #{victim_name} (ID: #{victim_id})")

          # For test notifications, we'll bypass the normal notification criteria
          # and directly enrich and send the notification
          Logger.info("TEST NOTIFICATION: Bypassing normal notification criteria for test")

          case ZKillService.get_enriched_killmail(kill_id) do
            {:ok, enriched_kill} ->
              Logger.info("TEST NOTIFICATION: Successfully enriched kill_id=#{kill_id}")

              # Send the notification directly
              Logger.info("TEST NOTIFICATION: Sending Discord notification for test kill")
              notify_kill(enriched_kill, kill_id)
              Logger.info("TEST NOTIFICATION: Successfully sent Discord notification for test kill")

              {:ok, kill_id}

            {:error, err} ->
              Logger.error("TEST NOTIFICATION: Failed to enrich kill #{kill_id}: #{inspect(err)}")
              {:error, :enrichment_failed}
          end
        else
          Logger.error("TEST NOTIFICATION: No kill_id found in recent kill data")
          {:error, :no_kill_id}
        end
    end
  end

  # Create a mock kill for testing when no real kills are available
  defp create_mock_kill do
    # Get a random system from tracked systems if available
    tracked_systems = CacheHelpers.get_tracked_systems()
    system = if length(tracked_systems) > 0 do
      Enum.random(tracked_systems)
    else
      %{"system_id" => "30000142", "system_name" => "Jita"}
    end

    system_id = system["system_id"] || system[:system_id] || "30000142"
    system_name = system["system_name"] || system[:alias] || "Jita"

    # Generate a random kill ID for the test
    kill_id = :rand.uniform(999_999_999)

    # Create a mock kill with all the necessary fields for the notification
    %{
      "killmail_id" => kill_id,
      "solar_system_id" => system_id,
      "solar_system_name" => system_name,
      "killmail_time" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "zkb" => %{
        "totalValue" => :rand.uniform(1_000_000_000) / 1.0,
        "points" => :rand.uniform(100),
        "url" => "https://zkillboard.com/kill/#{kill_id}/"
      },
      "victim" => %{
        "character_id" => "TEST#{:rand.uniform(10000)}",
        "character_name" => "Test Victim",
        "corporation_id" => "TEST#{:rand.uniform(10000)}",
        "corporation_name" => "Test Corporation",
        "alliance_id" => "TEST#{:rand.uniform(10000)}",
        "alliance_name" => "Test Alliance",
        "ship_type_id" => "TEST#{:rand.uniform(10000)}",
        "ship_type_name" => "Test Ship"
      },
      "attackers" => [
        %{
          "character_id" => "TEST#{:rand.uniform(10000)}",
          "character_name" => "Test Attacker",
          "corporation_id" => "TEST#{:rand.uniform(10000)}",
          "corporation_name" => "Test Attacker Corp",
          "alliance_id" => "TEST#{:rand.uniform(10000)}",
          "alliance_name" => "Test Attacker Alliance",
          "ship_type_id" => "TEST#{:rand.uniform(10000)}",
          "ship_type_name" => "Test Attacker Ship",
          "final_blow" => true
        }
      ]
    }
  end

  # Get the most recent kills
  def get_recent_kills do
    recent_kills = Process.get(@recent_kills_key, [])
    Logger.info("Returning #{length(recent_kills)} recent kills")
    recent_kills
  end
end
