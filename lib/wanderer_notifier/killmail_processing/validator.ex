defmodule WandererNotifier.KillmailProcessing.Validator do
  @moduledoc """
  Validation functions for killmail data.

  This module provides functions to validate killmail data before processing.
  It ensures that killmails have all required fields and data integrity checks
  are passed before further processing.

  The validator works with all killmail formats (KillmailData, KillmailResource,
  or raw maps) by using the Extractor module for consistent data access.

  ## Usage

  ```elixir
  # Validate a killmail has all required fields
  case Validator.validate_complete_data(killmail) do
    :ok -> # Process the killmail
    {:error, reason} -> # Handle the validation error
  end
  ```
  """

  alias WandererNotifier.KillmailProcessing.Extractor

  @doc """
  Validates that a killmail has complete data for processing.

  Checks for the presence of:
  - Killmail ID
  - Solar system ID
  - Solar system name
  - Victim data

  ## Parameters

  - `killmail`: Any killmail format (KillmailData, KillmailResource, or map)

  ## Returns

  - `:ok` if all required data is present
  - `{:error, reason}` with a string reason if validation fails

  ## Examples

      iex> Validator.validate_complete_data(valid_killmail)
      :ok

      iex> Validator.validate_complete_data(invalid_killmail)
      {:error, "Killmail ID missing"}
  """
  @spec validate_complete_data(Extractor.killmail_source()) :: :ok | {:error, String.t()}
  def validate_complete_data(killmail) do
    debug_data = Extractor.debug_data(killmail)

    field_checks = [
      {:killmail_id, debug_data.killmail_id, "Killmail ID missing"},
      {:system_id, debug_data.system_id, "Solar system ID missing"},
      {:system_name, debug_data.system_name, "Solar system name missing"},
      {:victim, debug_data.has_victim_data, "Victim data missing"}
    ]

    # Find first failure
    case Enum.find(field_checks, fn {_field, value, _msg} ->
           is_nil(value) or value == false
         end) do
      nil -> :ok
      {_field, _value, msg} -> {:error, msg}
    end
  end

  @doc """
  Normalizes killmail data from any source into a standard format.

  This function is used to convert legacy Killmail structs or raw data into
  a standardized format that can be used consistently throughout the application.

  ## Parameters

  - `killmail`: The killmail data to normalize (any format)

  ## Returns

  - Map with normalized killmail data
  """
  @spec normalize_killmail(Extractor.killmail_source()) :: map()
  def normalize_killmail(killmail) do
    # Extract core data using Extractor
    killmail_id = Extractor.get_killmail_id(killmail)
    zkb_data = Extractor.get_zkb_data(killmail) || %{}
    system_id = Extractor.get_system_id(killmail)
    system_name = Extractor.get_system_name(killmail) || "Unknown System"
    system_security = get_system_security(killmail)
    victim = Extractor.get_victim(killmail) || %{}
    attackers = Extractor.get_attackers(killmail) || []

    # Get time values and ensure they're proper DateTime objects, not just structs
    kill_time = extract_safe_datetime(Extractor.get_kill_time(killmail))
    processed_at = DateTime.utc_now()

    # Find the final blow attacker
    final_blow_attacker =
      Enum.find(attackers, fn attacker ->
        Map.get(attacker, "final_blow", false) == true
      end) || %{}

    # Build the normalized structure
    %{
      killmail_id: killmail_id,
      kill_time: kill_time,
      processed_at: processed_at,
      # Economic data
      total_value: Map.get(zkb_data, "totalValue", 0),
      points: Map.get(zkb_data, "points"),
      is_npc: Map.get(zkb_data, "npc", false),
      is_solo: Map.get(zkb_data, "solo", false),
      # System data
      solar_system_id: system_id,
      solar_system_name: system_name,
      solar_system_security: system_security,
      # Victim data
      victim_id: Map.get(victim, "character_id"),
      victim_name: Map.get(victim, "character_name"),
      victim_ship_id: Map.get(victim, "ship_type_id"),
      victim_ship_name: Map.get(victim, "ship_type_name") || "Unknown Ship",
      victim_corporation_id: Map.get(victim, "corporation_id"),
      victim_corporation_name: Map.get(victim, "corporation_name") || "Unknown Corp",
      victim_alliance_id: Map.get(victim, "alliance_id"),
      victim_alliance_name: Map.get(victim, "alliance_name"),
      # Attacker data
      attacker_count: length(attackers),
      final_blow_attacker_id: Map.get(final_blow_attacker, "character_id"),
      final_blow_attacker_name: Map.get(final_blow_attacker, "character_name") || "Unknown",
      final_blow_ship_id: Map.get(final_blow_attacker, "ship_type_id"),
      final_blow_ship_name: Map.get(final_blow_attacker, "ship_type_name") || "Unknown Ship",
      # Raw data preservation
      zkb_hash: Map.get(zkb_data, "hash"),
      full_victim_data: victim,
      full_attacker_data: attackers
    }
  end

  # Helper to safely extract a DateTime value or create a default
  defp extract_safe_datetime(value) do
    cond do
      is_nil(value) ->
        DateTime.utc_now()

      is_struct(value) && value.__struct__ == DateTime ->
        value

      is_binary(value) ->
        case DateTime.from_iso8601(value) do
          {:ok, datetime, _} -> datetime
          _ -> DateTime.utc_now()
        end

      true ->
        DateTime.utc_now()
    end
  end

  # Helper function to extract system security from different formats
  defp get_system_security(killmail) do
    cond do
      is_struct(killmail, KillmailResource) && Map.get(killmail, :solar_system_security) ->
        killmail.solar_system_security

      is_map(killmail) && Map.get(killmail, :solar_system_security) ->
        Map.get(killmail, :solar_system_security)

      is_map(killmail) && Map.get(killmail, :esi_data) &&
        is_map(Map.get(killmail, :esi_data)) &&
          Map.get(killmail.esi_data, "security_status") ->
        Map.get(killmail.esi_data, "security_status")

      true ->
        nil
    end
  end

  @doc """
  Extracts character involvement data from a killmail.

  This function builds a data structure representing how a specific character
  was involved in a killmail, either as attacker or victim.

  ## Parameters

  - `killmail`: The killmail data (any format)
  - `character_id`: The character ID to extract involvement for
  - `role`: The role of the character (:attacker or :victim)

  ## Returns

  - Map of involvement data or nil if character not found
  """
  @spec extract_character_involvement(Extractor.killmail_source(), String.t() | integer(), atom()) ::
          map() | nil
  def extract_character_involvement(killmail, character_id, :victim) do
    victim = Extractor.get_victim(killmail) || %{}
    victim_id_str = extract_id_str(victim, "character_id")
    character_id_str = to_string(character_id)

    if victim_id_str == character_id_str do
      %{
        character_id: character_id,
        character_role: :victim,
        ship_type_id: Map.get(victim, "ship_type_id"),
        ship_type_name: Map.get(victim, "ship_type_name") || "Unknown Ship",
        damage_done: 0,
        is_final_blow: false,
        weapon_type_id: nil,
        weapon_type_name: nil
      }
    else
      nil
    end
  end

  def extract_character_involvement(killmail, character_id, :attacker) do
    attackers = Extractor.get_attackers(killmail) || []
    character_id_str = to_string(character_id)

    attacker = find_matching_attacker(attackers, character_id_str)

    if attacker do
      %{
        character_id: character_id,
        character_role: :attacker,
        ship_type_id: Map.get(attacker, "ship_type_id"),
        ship_type_name: Map.get(attacker, "ship_type_name") || "Unknown Ship",
        damage_done: Map.get(attacker, "damage_done", 0),
        is_final_blow: Map.get(attacker, "final_blow", false),
        weapon_type_id: Map.get(attacker, "weapon_type_id"),
        weapon_type_name: Map.get(attacker, "weapon_type_name")
      }
    else
      nil
    end
  end

  def extract_character_involvement(_killmail, _character_id, _role), do: nil

  # Helper to extract ID as string
  defp extract_id_str(entity, key) do
    id = Map.get(entity, key)
    id && to_string(id)
  end

  # Helper to find matching attacker
  defp find_matching_attacker(attackers, character_id_str) do
    Enum.find(attackers, fn attacker ->
      attacker_id_str = extract_id_str(attacker, "character_id")
      attacker_id_str == character_id_str
    end)
  end
end
