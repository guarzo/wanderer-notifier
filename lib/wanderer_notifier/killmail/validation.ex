defmodule WandererNotifier.Killmail.Validation do
  @moduledoc """
  Module for killmail validation and transformation.
  Provides functions to validate and convert killmails between different formats.
  """

  alias WandererNotifier.Logger.Logger, as: AppLogger
  alias WandererNotifier.Utils.TypeHelpers
  alias WandererNotifier.Resources.Killmail, as: KillmailResource
  require Logger

  @doc """
  Validates a killmail for completeness and data quality.

  ## Parameters
  - killmail: A killmail map or struct to validate

  ## Returns
  - {:ok, killmail} if valid
  - {:error, reasons} if invalid with a list of validation failures
  """
  def validate_killmail(killmail) do
    # Required fields
    missing_fields = []

    # Check for basic required fields
    missing_fields =
      if has_required_data?(killmail) do
        missing_fields
      else
        ["Missing required data" | missing_fields]
      end

    # Add ZKB check
    missing_fields =
      if has_zkb_data?(killmail) do
        missing_fields
      else
        ["Missing zkb data" | missing_fields]
      end

    # Check key fields
    missing_fields =
      if has_required_data?(killmail) do
        fields_to_check = [
          {"solar_system_id", "Missing solar system ID"},
          {"solar_system_name", "Missing solar system name"},
          {"kill_time", "Missing killmail time"}
        ]

        Enum.reduce(fields_to_check, missing_fields, fn {field, error}, acc ->
          if has_field?(killmail, field) do
            acc
          else
            [error | acc]
          end
        end)
      else
        missing_fields
      end

    # Check for placeholder values
    placeholder_fields = []

    # Check system name - only fail for exactly "Unknown System"
    placeholder_fields =
      if get_field(killmail, "solar_system_name") == "Unknown System" do
        ["Solar system name is placeholder (Unknown System)" | placeholder_fields]
      else
        placeholder_fields
      end

    # Combine all errors
    all_errors = missing_fields ++ placeholder_fields

    if Enum.empty?(all_errors) do
      {:ok, killmail}
    else
      {:error, all_errors}
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
    get_field(killmail, field) != nil
  end

  # Helper to get a field value from different killmail formats
  defp get_field(killmail, field) do
    field_atom = String.to_atom(field)
    field_str = field

    case killmail do
      %KillmailResource{} -> Map.get(killmail, field_atom)
      %{esi_data: esi_data} when not is_nil(esi_data) -> Map.get(esi_data, field_str)
      %{} -> Map.get(killmail, field_atom) || Map.get(killmail, field_str)
      _ -> nil
    end
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
    # Extract killmail ID
    killmail_id = killmail_id || 0

    # Extract kill time from esi_data
    kill_time =
      case Map.get(esi_data, "killmail_time") do
        nil -> DateTime.utc_now()
        time -> parse_datetime(time)
      end

    # Extract victim data
    victim = Map.get(esi_data, "victim") || %{}
    victim_id = Map.get(victim, "character_id")
    victim_name = Map.get(victim, "character_name")
    victim_ship_id = Map.get(victim, "ship_type_id")

    victim_ship_name =
      Map.get(victim, "ship_type_name") || Map.get(victim, "ship_type") || "Unknown Ship"

    victim_corporation_id = Map.get(victim, "corporation_id")
    victim_corporation_name = Map.get(victim, "corporation_name")
    victim_alliance_id = Map.get(victim, "alliance_id")
    victim_alliance_name = Map.get(victim, "alliance_name")

    # Extract system data
    solar_system_id = Map.get(esi_data, "solar_system_id")
    solar_system_name = Map.get(esi_data, "solar_system_name") || "Unknown System"
    region_id = Map.get(esi_data, "region_id")
    region_name = Map.get(esi_data, "region_name")

    # Get attackers
    attackers = Map.get(esi_data, "attackers") || []
    attacker_count = length(attackers)

    # Find final blow attacker
    final_blow_attacker =
      Enum.find(attackers, fn attacker ->
        Map.get(attacker, "final_blow", false) == true
      end)

    # Extract final blow attacker info
    final_blow_attacker_id = Map.get(final_blow_attacker || %{}, "character_id")
    final_blow_attacker_name = Map.get(final_blow_attacker || %{}, "character_name")
    final_blow_ship_id = Map.get(final_blow_attacker || %{}, "ship_type_id")

    final_blow_ship_name =
      Map.get(final_blow_attacker || %{}, "ship_type_name") ||
        Map.get(final_blow_attacker || %{}, "ship_type")

    # Extract value data from zkb
    total_value = parse_decimal(Map.get(zkb_data, "totalValue") || 0)
    points = Map.get(zkb_data, "points")
    is_npc = Map.get(zkb_data, "npc", false)
    is_solo = Map.get(zkb_data, "solo", false)
    zkb_hash = Map.get(zkb_data, "hash")

    # Return normalized structure - match fields exactly with Killmail resource
    %{
      killmail_id: killmail_id,
      kill_time: kill_time,
      processed_at: DateTime.utc_now(),

      # Economic data
      total_value: total_value,
      points: points,
      is_npc: is_npc,
      is_solo: is_solo,

      # System information
      solar_system_id: solar_system_id,
      solar_system_name: solar_system_name,
      region_id: region_id,
      region_name: region_name,

      # Victim information
      victim_id: victim_id,
      victim_name: victim_name,
      victim_ship_id: victim_ship_id,
      victim_ship_name: victim_ship_name,
      victim_corporation_id: victim_corporation_id,
      victim_corporation_name: victim_corporation_name,
      victim_alliance_id: victim_alliance_id,
      victim_alliance_name: victim_alliance_name,

      # Attacker information
      attacker_count: attacker_count,
      final_blow_attacker_id: final_blow_attacker_id,
      final_blow_attacker_name: final_blow_attacker_name,
      final_blow_ship_id: final_blow_ship_id,
      final_blow_ship_name: final_blow_ship_name,

      # Raw data preservation
      zkb_hash: zkb_hash,
      full_victim_data: victim,
      full_attacker_data: attackers
    }
  end

  @doc """
  Extracts character involvement data from a killmail.

  ## Parameters
  - killmail: The normalized Killmail resource or map
  - character_id: The ID of the character
  - role: The role of the character (attacker/victim)

  ## Returns
  - Map of involvement data
  """
  def extract_character_involvement(killmail, character_id, role) do
    # Base attributes - these match the KillmailCharacterInvolvement resource
    attrs = %{
      character_id: character_id,
      # Ensure it's a proper atom
      character_role: String.to_atom(to_string(role))
    }

    # Specific attributes based on role
    role_specific_attrs =
      case role do
        :victim ->
          extract_victim_attributes(killmail, character_id)

        :attacker ->
          extract_attacker_attributes(killmail, character_id)

        _ ->
          %{}
      end

    # Merge base and role-specific attributes
    Map.merge(attrs, role_specific_attrs)
  end

  # Extract attributes for a victim
  defp extract_victim_attributes(killmail, character_id) do
    # Handle normalized killmail resource
    victim =
      if is_struct(killmail, KillmailResource) do
        # For normalized killmail resource
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
        # For raw data
        Map.get(killmail, "victim") || %{}
      end

    # Only include if the victim ID matches
    if to_string(Map.get(victim, "character_id", "")) == to_string(character_id) do
      %{
        ship_type_id: Map.get(victim, "ship_type_id"),
        ship_type_name:
          Map.get(victim, "ship_type_name") || Map.get(victim, "ship_type") || "Unknown Ship",
        damage_done: Map.get(victim, "damage_taken", 0),
        is_final_blow: false,
        weapon_type_id: nil,
        weapon_type_name: nil
      }
    else
      %{}
    end
  end

  # Extract attributes for an attacker
  defp extract_attacker_attributes(killmail, character_id) do
    # Get attackers based on killmail format
    attackers =
      if is_struct(killmail, KillmailResource) do
        # For normalized killmail resource, check if the final blow attacker matches
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
          # For non-final blow attackers, we need to check full_attacker_data
          killmail.full_attacker_data || []
        end
      else
        # For raw data
        Map.get(killmail, "attackers") || []
      end

    # Find the attacker in the list
    attacker =
      attackers
      |> Enum.find(fn a ->
        to_string(Map.get(a, "character_id", "")) == to_string(character_id)
      end)

    case attacker do
      nil ->
        %{}

      attacker ->
        %{
          ship_type_id: Map.get(attacker, "ship_type_id"),
          ship_type_name:
            Map.get(attacker, "ship_type_name") || Map.get(attacker, "ship_type") ||
              "Unknown Ship",
          damage_done: Map.get(attacker, "damage_done", 0),
          is_final_blow: Map.get(attacker, "final_blow", false),
          weapon_type_id: Map.get(attacker, "weapon_type_id"),
          weapon_type_name: Map.get(attacker, "weapon_type_name")
        }
    end
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

  # Maps can't be directly converted to Decimal, so log and return nil
  defp parse_decimal(value) when is_map(value) do
    AppLogger.kill_warn("Cannot convert map to Decimal", value: inspect(value))
    nil
  end

  # Lists can't be directly converted to Decimal, so log and return nil
  defp parse_decimal(value) when is_list(value) do
    AppLogger.kill_warn("Cannot convert list to Decimal", value: inspect(value))
    nil
  end

  # Catch-all for any other value types that might appear
  defp parse_decimal(value) do
    AppLogger.kill_warn("Cannot convert value to Decimal",
      value: inspect(value),
      type: TypeHelpers.typeof(value)
    )

    nil
  end
end
