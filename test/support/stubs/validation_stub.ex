defmodule WandererNotifier.Killmail.Validation do
  @moduledoc """
  Stub implementation of the Killmail.Validation module for testing.
  """

  alias WandererNotifier.Data.Killmail, as: KillmailStruct

  @doc """
  Normalize a killmail struct to the new model format.
  """
  def normalize_killmail(%KillmailStruct{} = killmail) do
    # Return a simple map with basic killmail fields
    %{
      killmail_id: killmail.killmail_id,
      kill_time: DateTime.utc_now(),
      total_value: get_value_from_zkb(killmail.zkb),
      victim_id: get_victim_id(killmail),
      victim_name: get_victim_name(killmail),
      victim_ship_id: get_victim_ship_id(killmail),
      victim_ship_name: get_victim_ship_name(killmail),
      solar_system_id: get_system_id(killmail),
      solar_system_name: get_system_name(killmail),
      final_blow_attacker_id: get_final_blow_id(killmail),
      final_blow_attacker_name: get_final_blow_name(killmail),
      final_blow_ship_name: get_final_blow_ship_name(killmail),
      attacker_count: get_attacker_count(killmail),
      zkb_hash: get_zkb_hash(killmail),
      full_attacker_data: get_attackers(killmail)
    }
  end

  @doc """
  Extract a character involvement record from a killmail.
  """
  def extract_character_involvement(%KillmailStruct{} = killmail, character_id, character_role) do
    case character_role do
      :victim ->
        extract_victim_involvement(killmail, character_id)

      :attacker ->
        extract_attacker_involvement(killmail, character_id)

      _ ->
        nil
    end
  end

  @doc """
  Validate a new killmail record before persistence.
  """
  def validate_killmail(killmail) do
    # Simple validation to ensure required fields are present
    required_fields = [:killmail_id, :kill_time, :solar_system_id, :solar_system_name]

    missing_fields =
      Enum.filter(required_fields, fn field ->
        is_nil(Map.get(killmail, field))
      end)

    if Enum.empty?(missing_fields) do
      {:ok, killmail}
    else
      {:error, "Missing required fields: #{Enum.join(missing_fields, ", ")}"}
    end
  end

  # Helper functions for extracting data from killmail

  defp get_value_from_zkb(zkb) do
    Map.get(zkb || %{}, "totalValue", 0)
  end

  defp get_victim_id(killmail) do
    victim = KillmailStruct.get_victim(killmail) || %{}
    Map.get(victim, "character_id")
  end

  defp get_victim_name(killmail) do
    victim = KillmailStruct.get_victim(killmail) || %{}
    Map.get(victim, "character_name", "Unknown Victim")
  end

  defp get_victim_ship_id(killmail) do
    victim = KillmailStruct.get_victim(killmail) || %{}
    Map.get(victim, "ship_type_id")
  end

  defp get_victim_ship_name(killmail) do
    victim = KillmailStruct.get_victim(killmail) || %{}
    Map.get(victim, "ship_type_name", "Unknown Ship")
  end

  defp get_system_id(killmail) do
    KillmailStruct.get_system_id(killmail)
  end

  defp get_system_name(killmail) do
    KillmailStruct.get(killmail, "solar_system_name", "Unknown System")
  end

  defp get_final_blow_id(killmail) do
    attackers = KillmailStruct.get_attacker(killmail) || []
    final_blow = Enum.find(attackers, fn a -> Map.get(a, "final_blow") == true end) || %{}
    Map.get(final_blow, "character_id")
  end

  defp get_final_blow_name(killmail) do
    attackers = KillmailStruct.get_attacker(killmail) || []
    final_blow = Enum.find(attackers, fn a -> Map.get(a, "final_blow") == true end) || %{}
    Map.get(final_blow, "character_name", "Unknown Attacker")
  end

  defp get_final_blow_ship_name(killmail) do
    attackers = KillmailStruct.get_attacker(killmail) || []
    final_blow = Enum.find(attackers, fn a -> Map.get(a, "final_blow") == true end) || %{}
    Map.get(final_blow, "ship_type_name", "Unknown Ship")
  end

  defp get_attacker_count(killmail) do
    attackers = KillmailStruct.get_attacker(killmail) || []
    length(attackers)
  end

  defp get_zkb_hash(killmail) do
    Map.get(killmail.zkb || %{}, "hash", "unknown")
  end

  defp get_attackers(killmail) do
    KillmailStruct.get_attacker(killmail) || []
  end

  # Helper functions for extracting involvement data

  defp extract_victim_involvement(killmail, character_id) do
    victim = KillmailStruct.get_victim(killmail) || %{}
    victim_id = Map.get(victim, "character_id")

    if victim_id == character_id do
      %{
        character_id: character_id,
        character_name: Map.get(victim, "character_name", "Unknown Victim"),
        ship_type_id: Map.get(victim, "ship_type_id"),
        ship_type_name: Map.get(victim, "ship_type_name", "Unknown Ship"),
        damage_done: 0,
        is_final_blow: false
      }
    else
      nil
    end
  end

  defp extract_attacker_involvement(killmail, character_id) do
    attackers = KillmailStruct.get_attacker(killmail) || []

    attacker =
      Enum.find(attackers, fn a ->
        Map.get(a, "character_id") == character_id
      end)

    if attacker do
      %{
        character_id: character_id,
        character_name: Map.get(attacker, "character_name", "Unknown Attacker"),
        ship_type_id: Map.get(attacker, "ship_type_id"),
        ship_type_name: Map.get(attacker, "ship_type_name", "Unknown Ship"),
        damage_done: Map.get(attacker, "damage_done", 0),
        is_final_blow: Map.get(attacker, "final_blow") == true,
        weapon_type_id: Map.get(attacker, "weapon_type_id"),
        weapon_type_name: Map.get(attacker, "weapon_type_name")
      }
    else
      nil
    end
  end
end
