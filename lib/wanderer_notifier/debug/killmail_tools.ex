defmodule WandererNotifier.Debug.KillmailTools do
  @moduledoc """
  Debugging tools for analyzing killmail processing and persistence.
  """

  @doc """
  Enable detailed logging for the next killmail received.

  This will log detailed information about how the killmail would be persisted,
  showing exactly what data would be stored for both the victim and a sample attacker.

  ## Returns
  * `:ok` - Logging for next killmail has been enabled
  """
  def log_next_killmail do
    # Set a flag in application env to enable logging
    Application.put_env(:wanderer_notifier, :log_next_killmail, true)

    IO.puts("""

    🔍 Next killmail will be logged with detailed persistence information.

    Watch for console output showing:
     - Full killmail structure
     - What would be persisted for victim
     - What would be persisted for attacker
     - All key fields and relationships

    This happens automatically when the next killmail is received.
    """)

    :ok
  end

  @doc """
  Process a killmail for debugging persistence.
  This function is called by the websocket handler when a killmail is received
  and debug logging is enabled.
  """
  def process_killmail_debug(json_data) when is_map(json_data) do
    kill_id = extract_killmail_id(json_data)

    IO.puts("\n=====================================================")
    IO.puts("🔍 ANALYZING KILLMAIL #{kill_id} FOR PERSISTENCE")
    IO.puts("=====================================================\n")

    # Log the victim data - what would be persisted if this character was tracked
    log_victim_persistence_data(json_data, kill_id)

    # Log a sample attacker data - what would be persisted if this character was tracked
    log_attacker_persistence_data(json_data, kill_id)

    # Don't reset the flag here - let the enrichment step also use it
    # The flag will be reset after enrichment logging is complete

    :ok
  end

  # Extract the killmail ID from different possible formats
  defp extract_killmail_id(json_data) do
    cond do
      Map.has_key?(json_data, "killmail_id") ->
        json_data["killmail_id"]

      Map.has_key?(json_data, "zkb") && Map.has_key?(json_data["zkb"], "killmail_id") ->
        json_data["zkb"]["killmail_id"]

      true ->
        "unknown"
    end
  end

  # Log what would be persisted for the victim
  defp log_victim_persistence_data(json_data, kill_id) do
    victim = Map.get(json_data, "victim") || %{}
    victim_id = Map.get(victim, "character_id", "unknown")
    victim_name = Map.get(victim, "character_name", "Unknown Victim")

    IO.puts("------ VICTIM PERSISTENCE DATA ------")
    IO.puts("KILLMAIL_ID: #{kill_id}")
    IO.puts("CHARACTER_ID: #{victim_id}")
    IO.puts("CHARACTER_NAME: #{victim_name}")
    IO.puts("ROLE: victim")

    # Basic killmail info
    log_killmail_base_data(json_data)

    # Ship info
    ship_type_id = Map.get(victim, "ship_type_id", "unknown")
    ship_type_name = Map.get(victim, "ship_type_name", "unknown")

    IO.puts("SHIP_TYPE_ID: #{ship_type_id}")
    IO.puts("SHIP_TYPE_NAME: #{ship_type_name}")

    # Corp/alliance info
    corp_id = Map.get(victim, "corporation_id", "unknown")
    corp_name = Map.get(victim, "corporation_name", "unknown")
    alliance_id = Map.get(victim, "alliance_id", "unknown")
    alliance_name = Map.get(victim, "alliance_name", "unknown")

    IO.puts("CORPORATION_ID: #{corp_id}")
    IO.puts("CORPORATION_NAME: #{corp_name}")
    IO.puts("ALLIANCE_ID: #{alliance_id}")
    IO.puts("ALLIANCE_NAME: #{alliance_name}")

    IO.puts("\n")
  end

  # Log what would be persisted for a sample attacker (first one)
  defp log_attacker_persistence_data(json_data, kill_id) do
    attackers = Map.get(json_data, "attackers") || []

    if Enum.empty?(attackers) do
      IO.puts("------ ATTACKER PERSISTENCE DATA ------")
      IO.puts("NO ATTACKERS FOUND")
      IO.puts("\n")
      :ok
    else
      # Use first attacker (or final blow attacker if available)
      attacker =
        Enum.find(attackers, &Map.get(&1, "final_blow", false)) ||
          List.first(attackers)

      attacker_id = Map.get(attacker, "character_id", "unknown")
      attacker_name = Map.get(attacker, "character_name", "Unknown Attacker")

      IO.puts("------ ATTACKER PERSISTENCE DATA ------")
      IO.puts("KILLMAIL_ID: #{kill_id}")
      IO.puts("CHARACTER_ID: #{attacker_id}")
      IO.puts("CHARACTER_NAME: #{attacker_name}")
      IO.puts("ROLE: attacker")
      IO.puts("FINAL_BLOW: #{Map.get(attacker, "final_blow", false)}")

      # Basic killmail info
      log_killmail_base_data(json_data)

      # Ship info
      ship_type_id = Map.get(attacker, "ship_type_id", "unknown")
      ship_type_name = Map.get(attacker, "ship_type_name", "unknown")

      IO.puts("SHIP_TYPE_ID: #{ship_type_id}")
      IO.puts("SHIP_TYPE_NAME: #{ship_type_name}")

      # Weapon info
      weapon_type_id = Map.get(attacker, "weapon_type_id", "unknown")
      weapon_type_name = Map.get(attacker, "weapon_type_name", "unknown")

      IO.puts("WEAPON_TYPE_ID: #{weapon_type_id}")
      IO.puts("WEAPON_TYPE_NAME: #{weapon_type_name}")

      # Corp/alliance info
      corp_id = Map.get(attacker, "corporation_id", "unknown")
      corp_name = Map.get(attacker, "corporation_name", "unknown")
      alliance_id = Map.get(attacker, "alliance_id", "unknown")
      alliance_name = Map.get(attacker, "alliance_name", "unknown")

      IO.puts("CORPORATION_ID: #{corp_id}")
      IO.puts("CORPORATION_NAME: #{corp_name}")
      IO.puts("ALLIANCE_ID: #{alliance_id}")
      IO.puts("ALLIANCE_NAME: #{alliance_name}")

      IO.puts("\n")

      :ok
    end
  end

  # Log basic killmail data that's shared between victim and attacker records
  defp log_killmail_base_data(json_data) do
    # Solar system info
    solar_system_id = Map.get(json_data, "solar_system_id", "unknown")
    solar_system_name = Map.get(json_data, "solar_system_name", "unknown")

    IO.puts("SOLAR_SYSTEM_ID: #{solar_system_id}")
    IO.puts("SOLAR_SYSTEM_NAME: #{solar_system_name}")

    # ZKB data
    zkb_data = Map.get(json_data, "zkb", %{})
    total_value = Map.get(zkb_data, "totalValue", "unknown")
    zkb_hash = Map.get(zkb_data, "hash", "unknown")

    IO.puts("ZKB_HASH: #{zkb_hash}")
    IO.puts("TOTAL_VALUE: #{total_value}")

    # Timestamp
    kill_time =
      Map.get(json_data, "killmail_time") ||
        Map.get(json_data, "killTime") ||
        "unknown"

    IO.puts("KILL_TIME: #{kill_time}")
  end
end
