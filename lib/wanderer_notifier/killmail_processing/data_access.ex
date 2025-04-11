defmodule WandererNotifier.KillmailProcessing.DataAccess do
  @moduledoc """
  Helper functions for accessing data from the KillmailData struct.

  This module provides a simpler, more direct approach to accessing data from the
  KillmailData struct. It is intended as a replacement for the Extractor module
  during the transition to direct struct access.

  ## Direct Access vs. Extractor

  The original Extractor module was designed to handle multiple different killmail
  data formats, but with the standardization on the flattened KillmailData struct,
  most of this complexity is no longer needed.

  ### Before (using Extractor):

  ```elixir
  system_id = Extractor.get_system_id(killmail)
  victim_id = Extractor.get_victim_character_id(killmail)
  ```

  ### After (direct struct access):

  ```elixir
  system_id = killmail.solar_system_id
  victim_id = killmail.victim_id
  ```

  This module serves as a transition tool with helpers for complex data access
  patterns that aren't as simple as direct field access.
  """

  alias WandererNotifier.KillmailProcessing.KillmailData

  @doc """
  Get basic fields from a KillmailData struct for debugging.

  ## Parameters
    - killmail: The KillmailData struct

  ## Returns
    - Map with key debug information
  """
  @spec debug_info(KillmailData.t()) :: map()
  def debug_info(%KillmailData{} = killmail) do
    %{
      killmail_id: killmail.killmail_id,
      system_id: killmail.solar_system_id,
      system_name: killmail.solar_system_name,
      victim_id: killmail.victim_id,
      victim_name: killmail.victim_name,
      attacker_count: killmail.attacker_count || 0
    }
  end

  @doc """
  Find an attacker by character ID in the attackers list.

  ## Parameters
    - killmail: The KillmailData struct
    - character_id: The character ID to find

  ## Returns
    - The attacker map if found, nil otherwise
  """
  @spec find_attacker(KillmailData.t(), integer() | String.t()) :: map() | nil
  def find_attacker(%KillmailData{attackers: attackers}, character_id) when is_list(attackers) do
    character_id_str = to_string(character_id)

    Enum.find(attackers, fn attacker ->
      attacker_id = Map.get(attacker, "character_id")
      to_string(attacker_id) == character_id_str
    end)
  end

  def find_attacker(_, _), do: nil

  @doc """
  Determine if a character is involved in a killmail and their role.

  ## Parameters
    - killmail: The KillmailData struct
    - character_id: The character ID to check

  ## Returns
    - {:victim, victim_data} if the character is the victim
    - {:attacker, attacker_data} if the character is an attacker
    - nil if the character is not involved
  """
  @spec character_involvement(KillmailData.t(), integer() | String.t()) ::
          {:victim, map()} | {:attacker, map()} | nil
  def character_involvement(%KillmailData{} = killmail, character_id) do
    character_id_str = to_string(character_id)

    # Check if character is the victim
    if killmail.victim_id && to_string(killmail.victim_id) == character_id_str do
      victim_data = %{
        "character_id" => killmail.victim_id,
        "character_name" => killmail.victim_name,
        "ship_type_id" => killmail.victim_ship_id,
        "ship_type_name" => killmail.victim_ship_name
      }

      {:victim, victim_data}
    else
      # Check if character is an attacker
      attacker = find_attacker(killmail, character_id)
      if attacker, do: {:attacker, attacker}, else: nil
    end
  end

  @doc """
  Get all character IDs involved in a killmail.

  ## Parameters
    - killmail: The KillmailData struct

  ## Returns
    - List of character IDs (victim + all attackers)
  """
  @spec all_character_ids(KillmailData.t()) :: list(integer())
  def all_character_ids(%KillmailData{} = killmail) do
    # Start with victim if present
    victim_id = killmail.victim_id

    # Extract attacker IDs
    attacker_ids =
      if is_list(killmail.attackers) do
        Enum.map(killmail.attackers, fn attacker ->
          Map.get(attacker, "character_id")
        end)
        |> Enum.reject(&is_nil/1)
      else
        []
      end

    # Combine and remove duplicates
    ([victim_id] ++ attacker_ids)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  @doc """
  Get a human-readable summary of the killmail.

  ## Parameters
    - killmail: The KillmailData struct

  ## Returns
    - String with killmail summary
  """
  @spec summary(KillmailData.t()) :: String.t()
  def summary(%KillmailData{} = killmail) do
    victim_name = killmail.victim_name || "Unknown"
    victim_ship = killmail.victim_ship_name || "Unknown Ship"
    system_name = killmail.solar_system_name || "Unknown System"

    "Killmail ##{killmail.killmail_id}: #{victim_name} lost a #{victim_ship} in #{system_name}"
  end
end
