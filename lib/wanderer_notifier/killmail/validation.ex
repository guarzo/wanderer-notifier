defmodule WandererNotifier.Killmail.Validation do
  @moduledoc """
  Validation functions for the new killmail models.
  """

  alias WandererNotifier.Resources.Killmail
  alias WandererNotifier.Resources.KillmailCharacterInvolvement
  alias WandererNotifier.Logger.Logger, as: AppLogger

  @doc """
  Validate a new killmail record before persistence.

  ## Parameters
  - killmail: Map containing killmail attributes

  ## Returns
  - {:ok, validated_killmail} if valid
  - {:error, reason} if validation fails
  """
  def validate_killmail(killmail) when is_map(killmail) do
    required_fields = [:killmail_id, :kill_time, :solar_system_id]

    # Check required fields
    missing_fields = Enum.filter(required_fields, &is_nil(Map.get(killmail, &1)))

    if Enum.empty?(missing_fields) do
      # Ensure solar_system_name if we have solar_system_id
      killmail = ensure_field_defaults(killmail)

      # Convert any placeholder values
      killmail = sanitize_placeholder_values(killmail)

      # Create or validate against Killmail resource if needed
      {:ok, _} = validate_against_resource_schema(killmail, Killmail)

      {:ok, killmail}
    else
      # Format missing fields for error reporting
      fields_str = Enum.map_join(missing_fields, ", ", &to_string/1)

      AppLogger.kill_error("Killmail validation failed - missing required fields", %{
        killmail_id: Map.get(killmail, :killmail_id),
        missing_fields: fields_str
      })

      {:error, "Missing required fields: #{fields_str}"}
    end
  end

  @doc """
  Validate a character involvement record before persistence.

  ## Parameters
  - involvement: Map containing character involvement attributes

  ## Returns
  - {:ok, validated_involvement} if valid
  - {:error, reason} if validation fails
  """
  def validate_involvement(involvement) when is_map(involvement) do
    required_fields = [:character_id, :character_role, :killmail_id]

    # Check required fields
    missing_fields = Enum.filter(required_fields, &is_nil(Map.get(involvement, &1)))

    if Enum.empty?(missing_fields) do
      # Validate character role is a supported value
      if validate_character_role(involvement.character_role) do
        # Create or validate against KillmailCharacterInvolvement resource if needed
        {:ok, _} = validate_against_resource_schema(involvement, KillmailCharacterInvolvement)

        {:ok, involvement}
      else
        {:error, "Invalid character_role: #{inspect(involvement.character_role)}"}
      end
    else
      # Format missing fields for error reporting
      fields_str = Enum.map_join(missing_fields, ", ", &to_string/1)

      AppLogger.kill_error("Character involvement validation failed - missing required fields", %{
        character_id: Map.get(involvement, :character_id),
        killmail_id: Map.get(involvement, :killmail_id),
        missing_fields: fields_str
      })

      {:error, "Missing required fields: #{fields_str}"}
    end
  end

  # Ensure certain fields have default values if not present
  defp ensure_field_defaults(killmail) do
    killmail
    |> ensure_system_name()
    |> ensure_boolean_defaults()
    |> ensure_numeric_defaults()
  end

  # Set a default system name if not present but we have an ID
  defp ensure_system_name(%{solar_system_id: id} = killmail) when not is_nil(id) do
    if is_nil(killmail[:solar_system_name]) do
      Map.put(killmail, :solar_system_name, "Unknown System")
    else
      killmail
    end
  end

  defp ensure_system_name(killmail), do: killmail

  # Ensure boolean fields have default values
  defp ensure_boolean_defaults(killmail) do
    defaults = [
      {:is_npc, false},
      {:is_solo, false}
    ]

    Enum.reduce(defaults, killmail, fn {field, default}, acc ->
      if is_nil(Map.get(acc, field)) do
        Map.put(acc, field, default)
      else
        acc
      end
    end)
  end

  # Ensure numeric fields have default values
  defp ensure_numeric_defaults(killmail) do
    defaults = [
      {:points, 0},
      {:attacker_count, 0}
    ]

    Enum.reduce(defaults, killmail, fn {field, default}, acc ->
      if is_nil(Map.get(acc, field)) do
        Map.put(acc, field, default)
      else
        acc
      end
    end)
  end

  # Sanitize any placeholder values to more appropriate defaults
  defp sanitize_placeholder_values(killmail) do
    # Replace "Unknown System" with better placeholder if we don't have a real system name
    if killmail[:solar_system_name] == "Unknown System" && !is_nil(killmail[:solar_system_id]) do
      Map.put(killmail, :solar_system_name, "System ##{killmail.solar_system_id}")
    else
      killmail
    end
  end

  # Validate character role is one of the allowed values
  defp validate_character_role(role) when is_atom(role) do
    role in [:attacker, :victim]
  end

  defp validate_character_role(_), do: false

  # Validate against Ash resource schema
  # This function is a placeholder for more complex validation if needed
  defp validate_against_resource_schema(attributes, _resource) do
    # Simple validation check to use the resource module to avoid unused alias warnings
    # In a real implementation, this might do more complex validation against the resource schema
    {:ok, attributes}
  end

  @doc """
  Convert a Data.Killmail struct to the normalized model format.

  ## Parameters
  - killmail: The WandererNotifier.Data.Killmail struct

  ## Returns
  - Map with normalized fields ready for persistence
  """
  def normalize_killmail(%WandererNotifier.Data.Killmail{} = killmail) do
    zkb_data = killmail.zkb || %{}
    esi_data = killmail.esi_data || %{}
    victim_data = WandererNotifier.Data.Killmail.get_victim(killmail) || %{}
    attackers = WandererNotifier.Data.Killmail.get_attacker(killmail) || []

    # Find the attacker who got the final blow
    final_blow_attacker = Enum.find(attackers, &Map.get(&1, "final_blow", false)) || %{}

    # Build the normalized killmail map
    %{
      killmail_id: killmail.killmail_id,
      kill_time: parse_datetime(Map.get(esi_data, "killmail_time")),

      # Economic data from zKB
      total_value: parse_decimal(Map.get(zkb_data, "totalValue")),
      points: Map.get(zkb_data, "points"),
      is_npc: Map.get(zkb_data, "npc", false),
      is_solo: Map.get(zkb_data, "solo", false),

      # System information
      solar_system_id: Map.get(esi_data, "solar_system_id"),
      solar_system_name: Map.get(esi_data, "solar_system_name"),
      solar_system_security: parse_float(Map.get(esi_data, "security_status")),
      region_id: Map.get(esi_data, "region_id"),
      region_name: Map.get(esi_data, "region_name"),

      # Victim information
      victim_id: Map.get(victim_data, "character_id"),
      victim_name: Map.get(victim_data, "character_name"),
      victim_ship_id: Map.get(victim_data, "ship_type_id"),
      victim_ship_name: Map.get(victim_data, "ship_type_name"),
      victim_corporation_id: Map.get(victim_data, "corporation_id"),
      victim_corporation_name: Map.get(victim_data, "corporation_name"),
      victim_alliance_id: Map.get(victim_data, "alliance_id"),
      victim_alliance_name: Map.get(victim_data, "alliance_name"),

      # Basic attacker information
      attacker_count: length(attackers),
      final_blow_attacker_id: Map.get(final_blow_attacker, "character_id"),
      final_blow_attacker_name: Map.get(final_blow_attacker, "character_name"),
      final_blow_ship_id: Map.get(final_blow_attacker, "ship_type_id"),
      final_blow_ship_name: Map.get(final_blow_attacker, "ship_type_name"),

      # Raw data preservation
      zkb_hash: Map.get(zkb_data, "hash"),
      full_victim_data: victim_data,
      full_attacker_data: attackers
    }
  end

  @doc """
  Extract a character involvement record from a killmail for a specific character.

  ## Parameters
  - killmail: The Data.Killmail struct
  - character_id: The character ID
  - character_role: The role (:attacker or :victim)

  ## Returns
  - Map with normalized character involvement ready for persistence
  - nil if the character isn't found in the killmail
  """
  def extract_character_involvement(
        %WandererNotifier.Data.Killmail{} = killmail,
        character_id,
        character_role
      ) do
    case character_role do
      :victim ->
        extract_victim_involvement(killmail, character_id)

      :attacker ->
        extract_attacker_involvement(killmail, character_id)

      _ ->
        nil
    end
  end

  # Extract involvement data for a victim
  defp extract_victim_involvement(%WandererNotifier.Data.Killmail{} = killmail, character_id) do
    victim_data = WandererNotifier.Data.Killmail.get_victim(killmail) || %{}
    victim_character_id = Map.get(victim_data, "character_id")

    # Check if this victim matches the character_id
    if to_string(victim_character_id) == to_string(character_id) do
      %{
        ship_type_id: Map.get(victim_data, "ship_type_id"),
        ship_type_name: Map.get(victim_data, "ship_type_name"),
        damage_done: 0,
        is_final_blow: false,
        weapon_type_id: nil,
        weapon_type_name: nil
      }
    else
      nil
    end
  end

  # Extract involvement data for an attacker
  defp extract_attacker_involvement(%WandererNotifier.Data.Killmail{} = killmail, character_id) do
    attackers = WandererNotifier.Data.Killmail.get_attacker(killmail) || []

    # Find the attacker that matches the character_id
    attacker =
      Enum.find(attackers, fn attacker ->
        to_string(Map.get(attacker, "character_id", "")) == to_string(character_id)
      end)

    if attacker do
      %{
        ship_type_id: Map.get(attacker, "ship_type_id"),
        ship_type_name: Map.get(attacker, "ship_type_name"),
        damage_done: Map.get(attacker, "damage_done", 0),
        is_final_blow: Map.get(attacker, "final_blow", false),
        weapon_type_id: Map.get(attacker, "weapon_type_id"),
        weapon_type_name: Map.get(attacker, "weapon_type_name")
      }
    else
      nil
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

  defp parse_decimal(value) when is_integer(value) or is_float(value) do
    Decimal.new(value)
  end

  defp parse_decimal(value), do: value

  defp parse_float(nil), do: nil

  defp parse_float(value) when is_binary(value) do
    case Float.parse(value) do
      {float, ""} -> float
      _ -> nil
    end
  end

  defp parse_float(value) when is_integer(value), do: value / 1
  defp parse_float(value) when is_float(value), do: value
  defp parse_float(_), do: nil
end
