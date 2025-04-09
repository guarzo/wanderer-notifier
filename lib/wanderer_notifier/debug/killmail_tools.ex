# credo:disable-for-this-file
defmodule WandererNotifier.Debug.KillmailTools do
  @moduledoc """
  Debugging tools for analyzing killmail processing and persistence.
  """

  alias WandererNotifier.Data.Cache.Repository, as: CacheRepo

  alias WandererNotifier.KillmailProcessing.{
    Extractor,
    KillmailData,
    KillmailQueries,
    Validator
  }

  # alias WandererNotifier.Resources.Killmail, as: KillmailResource

  # Required fields for a valid killmail
  @required_fields [
    "killmail_id",
    "killmail_time",
    "solar_system_id",
    "solar_system_name"
  ]

  # Fields that should not have placeholder values
  @quality_fields [
    {"solar_system_name", "Unknown System"},
    {"ship_type_name", "Unknown Ship"}
  ]

  # Invalid character name patterns
  @invalid_character_names [
    "Unknown Character",
    "Unknown",
    "Unknown pilot",
    "Unknown Pilot"
  ]

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
     - Validation status of all required fields

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

    # Validate the killmail structure
    validate_killmail_structure(json_data)

    # Log the victim data - what would be persisted if this character was tracked
    log_victim_persistence_data(json_data, kill_id)

    # Log a sample attacker data - what would be persisted if this character was tracked
    log_attacker_persistence_data(json_data, kill_id)

    # Perform character data validation
    validate_character_data(json_data)

    # Convert json_data to a format suitable for validation
    killmail_data = %KillmailData{
      killmail_id: kill_id,
      zkb_data: Map.get(json_data, "zkb", %{}),
      esi_data:
        Map.drop(json_data, ["zkb", "killmail_id"])
        |> Map.put("solar_system_name", json_data["solar_system_name"] || "Unknown System")
    }

    # Get and display validation results using the Validator module
    case Validator.validate_complete_data(killmail_data) do
      :ok ->
        IO.puts("\n------ KILLMAIL VALIDATION PASSED ------")
        IO.puts("✅ All required fields are present")
        IO.puts("✅ No placeholder values detected")

      {:error, reasons} ->
        IO.puts("\n------ KILLMAIL VALIDATION FAILED ------")

        Enum.each(reasons, fn reason ->
          IO.puts("❌ #{reason}")
        end)
    end

    # Also show the debug data structure
    IO.puts("\n------ KILLMAIL DEBUG DATA ------")
    debug_data = debug_killmail_data(killmail_data)

    Enum.each(debug_data, fn {key, value} ->
      if is_map(value) || is_list(value) do
        IO.puts("#{key}: #{inspect(value, limit: 50)}")
      else
        IO.puts("#{key}: #{value}")
      end
    end)

    # Don't reset the flag here - let the enrichment step also use it
    # The flag will be reset after enrichment logging is complete

    :ok
  end

  # Validate the completeness of a killmail's structure
  defp validate_killmail_structure(json_data) do
    IO.puts("------ KILLMAIL STRUCTURE VALIDATION ------")

    # Check for required fields
    missing_fields =
      Enum.filter(@required_fields, fn field ->
        value = Map.get(json_data, field)
        is_nil(value) || value == "" || value == 0
      end)

    if Enum.empty?(missing_fields) do
      IO.puts("✅ All required fields are present")
    else
      IO.puts("⚠️ Missing required fields:")

      Enum.each(missing_fields, fn field ->
        IO.puts("  - #{field}")
      end)
    end

    # Check for data quality issues
    Enum.each(@quality_fields, fn {field, placeholder} ->
      value = Map.get(json_data, field)

      if value == placeholder do
        IO.puts("⚠️ Field has placeholder value: #{field} = \"#{placeholder}\"")
      end
    end)

    # Check ZKB data
    zkb_data = Map.get(json_data, "zkb", %{})
    total_value = Map.get(zkb_data, "totalValue")

    cond do
      is_nil(zkb_data) || zkb_data == %{} ->
        IO.puts("⚠️ Missing ZKB data")

      is_nil(total_value) || total_value == 0 ->
        IO.puts("⚠️ Missing or zero total value")

      true ->
        IO.puts("✅ ZKB data contains valid total value: #{total_value}")
    end

    IO.puts("\n")
  end

  # Validate character data quality
  defp validate_character_data(json_data) do
    IO.puts("------ CHARACTER DATA VALIDATION ------")

    # Check victim character
    victim = Extractor.get_victim(json_data)
    victim_id = victim && Map.get(victim, "character_id")
    victim_name = victim && Map.get(victim, "character_name")

    if victim_id do
      IO.puts("Victim ID: #{victim_id}, Name: #{victim_name || "not provided"}")
      validate_character_name(victim_name, "Victim")
    else
      IO.puts("⚠️ No victim character ID found")
    end

    # Check attackers
    attackers = Extractor.get_attackers(json_data) || []

    if Enum.empty?(attackers) do
      IO.puts("⚠️ No attackers found")
    else
      # Check a sample of attackers (first 3)
      sample_attackers = Enum.take(attackers, 3)

      IO.puts("Sample attackers (first #{length(sample_attackers)} of #{length(attackers)}):")

      Enum.each(sample_attackers, fn attacker ->
        attacker_id = Map.get(attacker, "character_id")
        attacker_name = Map.get(attacker, "character_name")

        if attacker_id do
          IO.puts("  Attacker ID: #{attacker_id}, Name: #{attacker_name || "not provided"}")
          validate_character_name(attacker_name, "Attacker")
        else
          IO.puts("  ⚠️ Attacker without character ID (possibly NPC)")
        end
      end)
    end

    IO.puts("\n")
  end

  # Validate character name quality
  defp validate_character_name(name, prefix) do
    cond do
      is_nil(name) || name == "" ->
        IO.puts("  ⚠️ #{prefix} character name is missing")

      name in @invalid_character_names ->
        IO.puts("  ⚠️ #{prefix} has invalid placeholder name: \"#{name}\"")

      is_binary(name) && String.starts_with?(name, "Unknown") ->
        IO.puts("  ⚠️ #{prefix} has suspicious name starting with \"Unknown\": \"#{name}\"")

      true ->
        IO.puts("  ✅ #{prefix} has valid name: \"#{name}\"")
    end
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
    victim = Extractor.get_victim(json_data) || %{}
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
    attackers = Extractor.get_attackers(json_data) || []

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

  @doc """
  Perform a complete validation of a killmail struct for debugging purposes.

  This runs through all the same validation checks that would be applied during persistence.

  ## Returns
  * `{:ok, report}` - Killmail is valid
  * `{:error, issues}` - Killmail has validation issues
  """
  def validate_killmail(killmail) do
    kill_id = killmail.killmail_id

    IO.puts("\n=====================================================")
    IO.puts("🔍 VALIDATING KILLMAIL #{kill_id}")
    IO.puts("=====================================================\n")

    # Check structure
    structure_result = validate_killmail_complete_structure(killmail)

    # Check victim character
    victim = Extractor.get_victim(killmail)
    victim_id = victim && Map.get(victim, "character_id")
    victim_name = victim && Map.get(victim, "character_name")
    victim_result = validate_character(victim_id, victim_name, "victim")

    # Check attackers
    attackers = Extractor.get_attackers(killmail) || []

    attacker_results =
      Enum.map(attackers, fn attacker ->
        attacker_id = Map.get(attacker, "character_id")
        attacker_name = Map.get(attacker, "character_name")
        validate_character(attacker_id, attacker_name, "attacker")
      end)

    # Get tracked character info by searching the ESI data
    # (esi_data contains the related_character_id as metadata)
    tracked_char_result =
      case extract_tracked_character_info(killmail) do
        {id, name} -> validate_character_tracked(id, name)
        nil -> {:warn, "No tracked character specified"}
      end

    # Summarize and generate report
    all_results = [structure_result, victim_result, tracked_char_result] ++ attacker_results
    errors = Enum.filter(all_results, fn {status, _} -> status == :error end)
    warnings = Enum.filter(all_results, fn {status, _} -> status == :warn end)

    # Final summary
    IO.puts("\n------ VALIDATION SUMMARY ------")

    if Enum.empty?(errors) do
      IO.puts("✅ Killmail is valid for persistence")

      if !Enum.empty?(warnings) do
        IO.puts("⚠️ Found #{length(warnings)} warnings:")
        Enum.each(warnings, fn {_, msg} -> IO.puts("  - #{msg}") end)
      end

      {:ok, %{killmail_id: kill_id, warnings: length(warnings)}}
    else
      IO.puts("❌ Killmail has validation errors:")
      Enum.each(errors, fn {_, msg} -> IO.puts("  - #{msg}") end)

      if !Enum.empty?(warnings) do
        IO.puts("\n⚠️ Also found #{length(warnings)} warnings:")
        Enum.each(warnings, fn {_, msg} -> IO.puts("  - #{msg}") end)
      end

      {:error,
       %{
         killmail_id: kill_id,
         errors: length(errors),
         warnings: length(warnings)
       }}
    end
  end

  # Validate full killmail structure
  defp validate_killmail_complete_structure(killmail) do
    IO.puts("------ KILLMAIL STRUCTURE VALIDATION ------")

    # Required fields for a valid killmail
    required_fields = [
      {:killmail_id, killmail.killmail_id, "Killmail ID missing"},
      {:kill_time, Map.get(killmail, :kill_time, nil), "Kill time missing"},
      {:solar_system_id, Extractor.get_system_id(killmail), "Solar system ID missing"},
      {:solar_system_name, Map.get(killmail, :solar_system_name, nil),
       "Solar system name missing"}
    ]

    # Quality checks
    quality_checks = [
      {Map.get(killmail, :solar_system_name) != "Unknown System",
       "Solar system name not properly enriched"},
      {killmail.zkb != nil && killmail.zkb != %{}, "ZKB data missing"},
      {is_map(killmail.zkb) && Map.get(killmail.zkb, "totalValue", 0) > 0,
       "Total value is zero or missing"}
    ]

    # Check for required fields
    missing_fields =
      Enum.filter(required_fields, fn {_, value, _} ->
        is_nil(value) || value == "" || value == 0
      end)

    # Check for quality issues
    quality_issues = Enum.filter(quality_checks, fn {is_valid, _} -> !is_valid end)

    # Log results
    if Enum.empty?(missing_fields) do
      IO.puts("✅ All required fields are present")
    else
      Enum.each(missing_fields, fn {_, _, msg} ->
        IO.puts("❌ #{msg}")
      end)
    end

    if Enum.empty?(quality_issues) do
      IO.puts("✅ All quality checks passed")
    else
      Enum.each(quality_issues, fn {_, msg} ->
        IO.puts("⚠️ #{msg}")
      end)
    end

    IO.puts("\n")

    # Determine overall result
    if !Enum.empty?(missing_fields) do
      {:error, "Missing required fields: #{length(missing_fields)}"}
    else
      if !Enum.empty?(quality_issues) do
        {:warn, "Quality issues: #{length(quality_issues)}"}
      else
        {:ok, "Structure valid"}
      end
    end
  end

  # Validate character
  defp validate_character(character_id, character_name, role) do
    IO.puts("------ #{String.upcase(role)} CHARACTER VALIDATION ------")

    cond do
      is_nil(character_id) ->
        IO.puts("❌ Missing character ID")
        {:error, "#{role} has missing character ID"}

      is_nil(character_name) || character_name == "" ->
        IO.puts("❌ Missing character name")
        {:error, "#{role} has missing character name"}

      character_name in @invalid_character_names ->
        IO.puts("❌ Invalid placeholder name: \"#{character_name}\"")
        {:error, "#{role} has invalid placeholder name: #{character_name}"}

      is_binary(character_name) && String.starts_with?(character_name, "Unknown") ->
        IO.puts("⚠️ Suspicious name starting with \"Unknown\": \"#{character_name}\"")
        {:warn, "#{role} has suspicious name: #{character_name}"}

      true ->
        IO.puts("✅ Valid character: ID=#{character_id}, Name=\"#{character_name}\"")
        {:ok, "#{role} character valid"}
    end
  end

  # Validate character tracking
  defp validate_character_tracked(character_id, character_name) do
    IO.puts("------ TRACKED CHARACTER VALIDATION ------")

    # Get tracked characters from cache
    alias WandererNotifier.Data.Cache.Keys, as: CacheKeys
    alias WandererNotifier.Data.Cache.Repository, as: CacheRepo

    characters = CacheRepo.get(CacheKeys.character_list()) || []

    # Check if character is tracked
    is_tracked =
      Enum.any?(characters, fn char ->
        tracked_id = Map.get(char, "character_id") || Map.get(char, :character_id)
        tracked_id && to_string(tracked_id) == to_string(character_id)
      end)

    # Handle validation
    cond do
      !is_tracked ->
        IO.puts("❌ Character is not in tracked characters list")
        {:error, "Character ID #{character_id} is not tracked"}

      character_name in @invalid_character_names ->
        IO.puts("❌ Invalid placeholder name: \"#{character_name}\"")
        {:error, "Tracked character has invalid name: #{character_name}"}

      is_binary(character_name) && String.starts_with?(character_name, "Unknown") ->
        IO.puts("⚠️ Suspicious name starting with \"Unknown\": \"#{character_name}\"")
        {:warn, "Tracked character has suspicious name: #{character_name}"}

      true ->
        IO.puts("✅ Valid tracked character: ID=#{character_id}, Name=\"#{character_name}\"")
        {:ok, "Tracked character valid"}
    end
  end

  # Extract tracked character ID and name from a killmail struct
  defp extract_tracked_character_info(killmail) do
    # First try to extract from metadata (if available)
    metadata = Map.get(killmail, :metadata, %{})

    case metadata do
      %{character_id: id, character_name: name} when not is_nil(id) and not is_nil(name) ->
        {id, name}

      %{character_id: id} when not is_nil(id) ->
        # Have ID but no name, try to find name in ESI data
        name = find_character_name_by_id(killmail, id)
        {id, name || "Unknown Character"}

      _ ->
        # No explicit metadata, try to find a tracked character
        find_first_tracked_character(killmail)
    end
  end

  # Find character name by ID in killmail data
  defp find_character_name_by_id(killmail, character_id) do
    # Convert ID to string for consistent comparison
    str_id = to_string(character_id)

    # Check victim
    victim = Extractor.get_victim(killmail)
    victim_id = victim && to_string(Map.get(victim, "character_id", ""))

    if victim_id == str_id do
      Map.get(victim, "character_name")
    else
      # Check attackers
      attackers = Extractor.get_attackers(killmail) || []

      matching_attacker =
        Enum.find(attackers, fn attacker ->
          attacker_id = to_string(Map.get(attacker, "character_id", ""))
          attacker_id == str_id
        end)

      matching_attacker && Map.get(matching_attacker, "character_name")
    end
  end

  # Find first tracked character in killmail
  defp find_first_tracked_character(killmail) do
    # Get tracked characters from cache
    alias WandererNotifier.Data.Cache.Keys, as: CacheKeys
    alias WandererNotifier.Data.Cache.Repository, as: CacheRepo

    tracked_characters = CacheRepo.get(CacheKeys.character_list()) || []
    tracked_ids = extract_tracked_character_ids(tracked_characters)

    # Check victim first
    victim = Extractor.get_victim(killmail)
    victim_id = victim && to_string(Map.get(victim, "character_id", ""))

    if victim_id && MapSet.member?(tracked_ids, victim_id) do
      {victim_id, Map.get(victim, "character_name", "Unknown Character")}
    else
      # Check attackers
      attackers = Extractor.get_attackers(killmail) || []

      tracked_attacker =
        Enum.find(attackers, fn attacker ->
          attacker_id = to_string(Map.get(attacker, "character_id", ""))
          attacker_id && MapSet.member?(tracked_ids, attacker_id)
        end)

      if tracked_attacker do
        {
          Map.get(tracked_attacker, "character_id"),
          Map.get(tracked_attacker, "character_name", "Unknown Character")
        }
      else
        nil
      end
    end
  end

  # Extract tracked character IDs as a MapSet for efficient lookups
  defp extract_tracked_character_ids(tracked_characters) do
    ids =
      Enum.map(tracked_characters, fn char ->
        id = Map.get(char, "character_id") || Map.get(char, :character_id)
        id && to_string(id)
      end)
      |> Enum.reject(&is_nil/1)

    MapSet.new(ids)
  end

  # Add a debug_killmail_data function to replace the old one
  defp debug_killmail_data(killmail) do
    %{
      # Basic fields
      killmail_id: killmail.killmail_id,

      # ESI fields (if present)
      solar_system_id: Extractor.get_system_id(killmail),
      solar_system_name: Map.get(killmail, :solar_system_name, nil),
      region_id: get_region_id(killmail),
      region_name: get_region_name(killmail),
      killmail_time: Map.get(killmail, :kill_time, nil),

      # Victim and attacker data
      victim: Extractor.get_victim(killmail),
      attackers_count: Extractor.get_attackers(killmail) |> length(),

      # ZKB data
      zkb_total_value: get_zkb_value(killmail),

      # Extra info
      has_esi_data: has_esi_data?(killmail),
      esi_data_keys: if(has_esi_data?(killmail), do: Map.keys(killmail.esi_data), else: []),
      zkb_keys: if(has_zkb_data?(killmail), do: Map.keys(get_zkb_data(killmail)), else: [])
    }
  end

  # Helper functions for accessing data in either format
  defp get_region_id(killmail) do
    Map.get(killmail, :region_id) ||
      (Map.get(killmail, :esi_data) && Map.get(killmail.esi_data, "region_id"))
  end

  defp get_region_name(killmail) do
    Map.get(killmail, :region_name) ||
      (Map.get(killmail, :esi_data) && Map.get(killmail.esi_data, "region_name"))
  end

  defp get_zkb_value(killmail) do
    if has_zkb_data?(killmail) do
      zkb_data = get_zkb_data(killmail)
      Map.get(zkb_data, "totalValue") || Map.get(zkb_data, "total_value")
    else
      nil
    end
  end

  defp get_zkb_data(killmail) do
    killmail.zkb_data || killmail.zkb || %{}
  end

  defp has_esi_data?(killmail) do
    is_map(killmail.esi_data) && killmail.esi_data != %{}
  end

  defp has_zkb_data?(killmail) do
    (is_map(killmail.zkb_data) && killmail.zkb_data != %{}) ||
      (is_map(killmail.zkb) && killmail.zkb != %{})
  end

  @doc """
  Fetch and diagnose a killmail record by ID.

  This function fetches a killmail record from the database using KillmailQueries
  and displays diagnostic information about it.

  ## Parameters
  - killmail_id: The ID of the killmail to fetch

  ## Returns
  - Diagnostic information about the killmail
  """
  def diagnose_killmail(killmail_id) when is_integer(killmail_id) do
    IO.puts("\n=====================================================")
    IO.puts("🔍 DIAGNOSING KILLMAIL #{killmail_id}")
    IO.puts("=====================================================\n")

    case KillmailQueries.exists?(killmail_id) do
      true ->
        IO.puts("✅ Killmail #{killmail_id} exists in database")

        case KillmailQueries.get(killmail_id) do
          {:ok, killmail} ->
            IO.puts("✅ Successfully retrieved killmail data")

            # Display basic killmail information
            solar_system_name = Extractor.get_system_name(killmail) || "Unknown"
            victim = Extractor.get_victim(killmail) || %{}
            victim_name = Map.get(victim, "character_name", "Unknown")
            attackers = Extractor.get_attackers(killmail) || []

            IO.puts("\n------ KILLMAIL INFORMATION ------")
            IO.puts("Killmail ID: #{killmail.killmail_id}")
            IO.puts("Solar System: #{solar_system_name}")
            IO.puts("Victim: #{victim_name}")
            IO.puts("Attackers: #{length(attackers)}")

            # Validate the killmail data
            case Validator.validate_complete_data(killmail) do
              :ok ->
                IO.puts("\n✅ Killmail data is valid")

              {:error, reasons} ->
                IO.puts("\n⚠️ Killmail data has validation issues:")

                Enum.each(reasons, fn reason ->
                  IO.puts("  - #{reason}")
                end)
            end

            {:ok, killmail}

          {:error, reason} ->
            IO.puts("❌ Failed to retrieve killmail: #{inspect(reason)}")
            {:error, reason}
        end

      false ->
        IO.puts("❌ Killmail #{killmail_id} does not exist in database")
        {:error, :not_found}
    end
  end

  def diagnose_killmail(killmail_id) when is_binary(killmail_id) do
    case Integer.parse(killmail_id) do
      {id, _} ->
        diagnose_killmail(id)

      :error ->
        IO.puts("❌ Invalid killmail ID: #{killmail_id}")
        {:error, :invalid_id}
    end
  end
end
