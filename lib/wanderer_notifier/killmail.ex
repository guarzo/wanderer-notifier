defmodule WandererNotifier.Killmail do
  @moduledoc """
  Utility functions for working with killmail data from various sources.

  NOTE: This module provides backward compatibility with existing code.
  New code should use the specialized modules in the KillmailProcessing namespace.

  @deprecated Use WandererNotifier.KillmailProcessing modules instead.

  ## Killmail Data Model

  Killmails are stored using two resources:

  1. `WandererNotifier.Resources.Killmail` - Stores the core killmail data
  2. `WandererNotifier.Resources.KillmailCharacterInvolvement` - Tracks which of your characters were involved

  ### Killmail Resource

  The Killmail resource holds the following information:

  - **Basic Metadata**: killmail_id, kill_time, processed_at
  - **Economic Data**: total_value, points, is_npc, is_solo
  - **System Information**: solar_system_id, solar_system_name, solar_system_security, region_id, region_name
  - **Victim Information**: victim_id, victim_name, victim_ship_id, victim_ship_name, victim_corporation_id, victim_corporation_name, victim_alliance_id, victim_alliance_name
  - **Basic Attacker Information**: attacker_count, final_blow_attacker_id, final_blow_attacker_name, final_blow_ship_id, final_blow_ship_name
  - **Raw Data**: zkb_hash, full_victim_data, full_attacker_data

  ### KillmailCharacterInvolvement Resource

  The KillmailCharacterInvolvement resource tracks how each character was involved in a killmail:

  - **Relationship**: References the killmail
  - **Character Information**: character_id, character_role (attacker or victim)
  - **Ship Information**: ship_type_id, ship_type_name
  - **Combat Details**: damage_done, is_final_blow, weapon_type_id, weapon_type_name
  """

  alias WandererNotifier.KillmailProcessing.Extractor
  alias WandererNotifier.KillmailProcessing.KillmailQueries
  alias WandererNotifier.KillmailProcessing.Validator
  alias WandererNotifier.Resources.Killmail, as: KillmailResource

  # Delegate database access functions to KillmailQueries
  defdelegate exists?(killmail_id), to: KillmailQueries
  defdelegate get(killmail_id), to: KillmailQueries
  defdelegate get_involvements(killmail_id), to: KillmailQueries

  defdelegate find_by_character(character_id, start_date, end_date, opts \\ []),
    to: KillmailQueries

  # Keep the get/3 function for backward compatibility
  def get(killmail, field, default \\ nil) do
    field_atom = if is_binary(field), do: String.to_atom(field), else: field
    field_str = if is_atom(field), do: Atom.to_string(field), else: field

    cond do
      # Check for struct with atom key
      is_struct(killmail) && Map.has_key?(killmail, field_atom) ->
        Map.get(killmail, field_atom)

      # Check map with atom key
      is_map(killmail) && Map.has_key?(killmail, field_atom) ->
        Map.get(killmail, field_atom)

      # Check map with string key
      is_map(killmail) && Map.has_key?(killmail, field_str) ->
        Map.get(killmail, field_str)

      true ->
        default
    end
  end

  # Delegate data extraction functions to Extractor
  defdelegate get_system_id(killmail), to: Extractor
  defdelegate get_system_name(killmail), to: Extractor
  defdelegate debug_data(killmail), to: Extractor

  # Alias victim and attacker functions to match old API
  @doc """
  Gets victim data from a killmail.
  @deprecated Use WandererNotifier.KillmailProcessing.Extractor.get_victim/1 instead.
  """
  def get_victim(killmail), do: Extractor.get_victim(killmail)

  @doc """
  Gets attacker data from a killmail.
  @deprecated Use WandererNotifier.KillmailProcessing.Extractor.get_attackers/1 instead.
  """
  def get_attacker(killmail), do: Extractor.get_attackers(killmail)

  # Delegate validation to Validator
  defdelegate validate_complete_data(killmail), to: Validator

  @doc """
  Finds a specific field in a killmail structure for a character.
  """
  def find_field(killmail, field, character_id, role) do
    case role do
      :victim ->
        victim = Extractor.get_victim(killmail)

        if to_string(Map.get(victim, "character_id", "")) == to_string(character_id) do
          Map.get(victim, field)
        else
          nil
        end

      :attacker ->
        attackers = Extractor.get_attackers(killmail)

        attacker =
          Enum.find(attackers, fn a ->
            to_string(Map.get(a, "character_id", "")) == to_string(character_id)
          end)

        if attacker, do: Map.get(attacker, field), else: nil

      _ ->
        nil
    end
  end
end
