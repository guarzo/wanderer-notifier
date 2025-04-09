defmodule WandererNotifier.Killmail.Validation do
  @moduledoc """
  Module for killmail validation and transformation.
  Provides functions to validate and convert killmails between different formats.
  """

  alias WandererNotifier.Logger.Logger, as: AppLogger
  alias WandererNotifier.Resources.Killmail, as: KillmailResource
  alias WandererNotifier.Utils.TypeHelpers
  require Logger

  @doc """
  Validates a killmail for completeness and data quality.

  ## Parameters
  - killmail: A killmail map or struct to validate

  ## Returns
  - {:ok, killmail} if valid
  - {:error, reason} if invalid with a list of validation failures
  """
  def validate_killmail(killmail) do
    missing_fields = check_required_fields(killmail)
    placeholder_fields = check_placeholder_values(killmail)
    all_errors = missing_fields ++ placeholder_fields

    if Enum.empty?(all_errors) do
      {:ok, killmail}
    else
      # Join the errors into a string for better error handling
      {:error, Enum.join(all_errors, ", ")}
    end
  end

  defp check_required_fields(killmail) do
    missing_fields = []

    missing_fields =
      if has_required_data?(killmail) do
        missing_fields
      else
        ["Missing required data" | missing_fields]
      end

    missing_fields =
      if has_zkb_data?(killmail) do
        missing_fields
      else
        ["Missing zkb data" | missing_fields]
      end

    if has_required_data?(killmail) do
      check_key_fields(killmail, missing_fields)
    else
      missing_fields
    end
  end

  defp check_key_fields(killmail, missing_fields) do
    # Special check for kill_time/killmail_time since we know this is failing
    has_time_field = has_field?(killmail, "kill_time") || has_field?(killmail, "killmail_time")

    missing_fields =
      if !has_time_field do
        ["Missing killmail time" | missing_fields]
      else
        missing_fields
      end

    # Check remaining required fields
    fields_to_check = [
      {"solar_system_id", "Missing solar system ID"},
      {"solar_system_name", "Missing solar system name"}
    ]

    Enum.reduce(fields_to_check, missing_fields, fn {field, error}, acc ->
      if has_field?(killmail, field) do
        acc
      else
        [error | acc]
      end
    end)
  end

  defp check_placeholder_values(killmail) do
    placeholder_fields = []

    if get_field(killmail, "solar_system_name") == "Unknown System" do
      ["Solar system name is placeholder (Unknown System)" | placeholder_fields]
    else
      placeholder_fields
    end
  end

  # Helper to check if killmail has required data
  defp has_required_data?(killmail) do
    case killmail do
      %KillmailResource{} -> true
      %{killmail_id: id} when not is_nil(id) -> true
      %{} = map -> Map.has_key?(map, :killmail_id) || Map.has_key?(map, "killmail_id")
      _ -> false
    end
  end

  # Helper to check if killmail has zkb data
  defp has_zkb_data?(killmail) do
    case killmail do
      %KillmailResource{} -> true
      %{zkb: zkb} when not is_nil(zkb) -> true
      %{zkb_data: zkb_data} when not is_nil(zkb_data) -> true
      _ -> false
    end
  end

  # Helper to check if killmail has a specific field
  defp has_field?(killmail, field) do
    # Simple implementation: just use get_field and check if result is non-nil
    get_field(killmail, field) != nil
  end

  # Helper to get a field value from different killmail formats
  defp get_field(killmail, field) do
    field_atom = String.to_atom(field)
    field_str = field

    # Simple lookup sequence: check direct access first, then ESI data
    value =
      cond do
        # Direct access with atom key
        is_map(killmail) && Map.has_key?(killmail, field_atom) ->
          Map.get(killmail, field_atom)

        # Direct access with string key
        is_map(killmail) && Map.has_key?(killmail, field_str) ->
          Map.get(killmail, field_str)

        # Check in ESI data
        is_map(killmail) && is_map(Map.get(killmail, :esi_data)) ->
          esi_data = Map.get(killmail, :esi_data)
          Map.get(esi_data, field_str)

        # Nothing found
        true ->
          nil
      end

    value
  end

  @doc """
  Normalizes killmail data from any source (API, webhook) into the proper
  normalized resource format used by the application.

  ## Parameters
  - killmail: The raw killmail data from an API or webhook

  ## Returns
  - Map with normalized killmail data matching the Killmail resource structure
  """
  def normalize_killmail(killmail) do
    # Extract basic data
    killmail_id = Map.get(killmail, :killmail_id) || Map.get(killmail, "killmail_id") || 0

    # Get zkb data (always a map)
    zkb_data =
      Map.get(killmail, :zkb_data) || Map.get(killmail, :zkb) || Map.get(killmail, "zkb") || %{}

    # Get ESI data (always a map)
    esi_data = Map.get(killmail, :esi_data) || Map.get(killmail, "esi_data") || %{}

    # Normalize the data using the common implementation
    normalize_generic_killmail(killmail_id, zkb_data, esi_data)
  end

  # Common implementation for normalization
  defp normalize_generic_killmail(killmail_id, zkb_data, esi_data) do
    %{
      killmail_id: killmail_id || 0,
      kill_time: extract_kill_time(esi_data),
      processed_at: DateTime.utc_now()
    }
    |> Map.merge(extract_economic_data(zkb_data))
    |> Map.merge(extract_system_data(esi_data))
    |> Map.merge(extract_victim_data(esi_data))
    |> Map.merge(extract_attacker_data(esi_data))
    |> Map.merge(preserve_raw_data(zkb_data, esi_data))
  end

  defp extract_kill_time(esi_data) do
    case Map.get(esi_data, "killmail_time") do
      nil -> DateTime.utc_now()
      time -> parse_datetime(time)
    end
  end

  defp extract_economic_data(zkb_data) do
    %{
      total_value: parse_decimal(Map.get(zkb_data, "totalValue") || 0),
      points: Map.get(zkb_data, "points"),
      is_npc: Map.get(zkb_data, "npc", false),
      is_solo: Map.get(zkb_data, "solo", false)
    }
  end

  defp extract_system_data(esi_data) do
    %{
      solar_system_id: Map.get(esi_data, "solar_system_id"),
      solar_system_name: Map.get(esi_data, "solar_system_name") || "Unknown System",
      region_id: Map.get(esi_data, "region_id"),
      region_name: Map.get(esi_data, "region_name")
    }
  end

  defp extract_victim_data(esi_data) do
    victim = Map.get(esi_data, "victim") || %{}

    %{
      victim_id: Map.get(victim, "character_id"),
      victim_name: Map.get(victim, "character_name"),
      victim_ship_id: Map.get(victim, "ship_type_id"),
      victim_ship_name:
        Map.get(victim, "ship_type_name") || Map.get(victim, "ship_type") || "Unknown Ship",
      victim_corporation_id: Map.get(victim, "corporation_id"),
      victim_corporation_name: Map.get(victim, "corporation_name"),
      victim_alliance_id: Map.get(victim, "alliance_id"),
      victim_alliance_name: Map.get(victim, "alliance_name")
    }
  end

  defp extract_attacker_data(esi_data) do
    attackers = Map.get(esi_data, "attackers") || []
    final_blow_attacker = find_final_blow_attacker(attackers)

    %{
      attacker_count: length(attackers),
      final_blow_attacker_id: Map.get(final_blow_attacker || %{}, "character_id"),
      final_blow_attacker_name: Map.get(final_blow_attacker || %{}, "character_name"),
      final_blow_ship_id: Map.get(final_blow_attacker || %{}, "ship_type_id"),
      final_blow_ship_name: get_final_blow_ship_name(final_blow_attacker)
    }
  end

  defp find_final_blow_attacker(attackers) do
    Enum.find(attackers, fn attacker ->
      Map.get(attacker, "final_blow", false) == true
    end)
  end

  defp get_final_blow_ship_name(final_blow_attacker) do
    Map.get(final_blow_attacker || %{}, "ship_type_name") ||
      Map.get(final_blow_attacker || %{}, "ship_type")
  end

  defp preserve_raw_data(zkb_data, esi_data) do
    %{
      zkb_hash: Map.get(zkb_data, "hash"),
      full_victim_data: Map.get(esi_data, "victim") || %{},
      full_attacker_data: Map.get(esi_data, "attackers") || []
    }
  end

  @doc """
  Extracts character involvement data from a killmail.

  ## Parameters
  - killmail: The normalized Killmail resource or map
  - character_id: The ID of the character
  - role: The role of the character (attacker/victim)

  ## Returns
  - Map of involvement data or nil if character not found
  """
  def extract_character_involvement(killmail, character_id, role) do
    case role do
      :victim ->
        victim = get_victim_data(killmail, character_id)

        if victim_matches_id?(victim, character_id) do
          build_base_attributes(character_id, role)
          |> Map.merge(build_victim_attributes(victim))
        else
          nil
        end

      :attacker ->
        attackers = get_attackers(killmail, character_id)
        attacker = find_matching_attacker(attackers, character_id)

        if attacker do
          build_base_attributes(character_id, role)
          |> Map.merge(build_attacker_attributes(attacker))
        else
          nil
        end

      _ ->
        nil
    end
  end

  defp build_base_attributes(character_id, role) do
    %{
      character_id: character_id,
      character_role: String.to_atom(to_string(role))
    }
  end

  # Extract attributes for a victim
  defp get_victim_data(killmail, character_id) do
    if is_struct(killmail, KillmailResource) do
      if to_string(killmail.victim_id || "") == to_string(character_id) do
        %{
          "character_id" => killmail.victim_id,
          "ship_type_id" => killmail.victim_ship_id,
          "ship_type_name" => killmail.victim_ship_name
        }
      else
        killmail.full_victim_data || %{}
      end
    else
      Map.get(killmail.esi_data || %{}, "victim") || %{}
    end
  end

  defp victim_matches_id?(victim, character_id) do
    to_string(Map.get(victim, "character_id", "")) == to_string(character_id)
  end

  defp build_victim_attributes(victim) do
    %{
      ship_type_id: Map.get(victim, "ship_type_id"),
      ship_type_name:
        Map.get(victim, "ship_type_name") || Map.get(victim, "ship_type") || "Unknown Ship",
      damage_done: Map.get(victim, "damage_taken", 0),
      is_final_blow: false,
      weapon_type_id: nil,
      weapon_type_name: nil
    }
  end

  # Extract attributes for an attacker
  defp get_attackers(killmail, character_id) do
    if is_struct(killmail, KillmailResource) do
      if killmail.final_blow_attacker_id &&
           to_string(killmail.final_blow_attacker_id) == to_string(character_id) do
        [
          %{
            "character_id" => killmail.final_blow_attacker_id,
            "ship_type_id" => killmail.final_blow_ship_id,
            "ship_type_name" => killmail.final_blow_ship_name,
            "final_blow" => true
          }
        ]
      else
        killmail.full_attacker_data || []
      end
    else
      Map.get(killmail.esi_data || %{}, "attackers") || []
    end
  end

  defp find_matching_attacker(attackers, character_id) do
    Enum.find(attackers, fn a ->
      to_string(Map.get(a, "character_id", "")) == to_string(character_id)
    end)
  end

  defp build_attacker_attributes(attacker) do
    %{
      ship_type_id: Map.get(attacker, "ship_type_id"),
      ship_type_name:
        Map.get(attacker, "ship_type_name") || Map.get(attacker, "ship_type") || "Unknown Ship",
      damage_done: Map.get(attacker, "damage_done", 0),
      is_final_blow: Map.get(attacker, "final_blow", false),
      weapon_type_id: Map.get(attacker, "weapon_type_id"),
      weapon_type_name: Map.get(attacker, "weapon_type_name")
    }
  end

  # Helper functions for data conversion

  defp parse_datetime(nil), do: nil

  defp parse_datetime(datetime_str) when is_binary(datetime_str) do
    case DateTime.from_iso8601(datetime_str) do
      {:ok, datetime, _} -> datetime
      _ -> nil
    end
  end

  defp parse_datetime(datetime), do: datetime

  defp parse_decimal(nil), do: nil

  defp parse_decimal(value) when is_binary(value) do
    case Decimal.parse(value) do
      {decimal, ""} -> decimal
      _ -> nil
    end
  end

  defp parse_decimal(value) when is_integer(value) do
    Decimal.new(value)
  end

  defp parse_decimal(value) when is_float(value) do
    # Convert float to decimal via string to avoid precision issues
    value |> Float.to_string() |> Decimal.parse() |> elem(0)
  end

  defp parse_decimal(value) when is_map(value) do
    log_invalid_decimal_conversion(value, "map")
    nil
  end

  defp parse_decimal(value) when is_list(value) do
    log_invalid_decimal_conversion(value, "list")
    nil
  end

  defp parse_decimal(value) do
    log_invalid_decimal_conversion(value, TypeHelpers.typeof(value))
    nil
  end

  defp log_invalid_decimal_conversion(value, type) do
    AppLogger.kill_warn("Cannot convert #{type} to Decimal",
      value: inspect(value),
      type: type
    )
  end
end
