defmodule WandererNotifier.KillmailProcessing.DataAccess do
  @moduledoc """
  Helper functions for accessing data from the KillmailData struct.

  @deprecated Please use WandererNotifier.Killmail.Utilities.DataAccess instead

  This module is deprecated and will be removed in a future release.
  All functionality has been moved to WandererNotifier.Killmail.Utilities.DataAccess.
  """

  require Logger
  alias WandererNotifier.KillmailProcessing.KillmailData
  alias WandererNotifier.Killmail.Core.Data
  alias WandererNotifier.Killmail.Utilities.DataAccess, as: NewDataAccess

  @doc """
  Get basic fields from a KillmailData struct for debugging.
  @deprecated Use WandererNotifier.Killmail.Utilities.DataAccess.debug_info/1 instead

  ## Parameters
    - killmail: The KillmailData struct

  ## Returns
    - Map with key debug information
  """
  @spec debug_info(KillmailData.t()) :: map()
  def debug_info(%KillmailData{} = killmail) do
    Logger.warning("Using deprecated DataAccess.debug_info/1, please update your code")

    # Convert to new format if needed
    case convert_to_new_format(killmail) do
      {:ok, new_data} -> NewDataAccess.debug_info(new_data)
      {:error, _} -> fallback_debug_info(killmail)
    end
  end

  # Fallback implementation if conversion fails
  defp fallback_debug_info(killmail) do
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
  @deprecated Use WandererNotifier.Killmail.Utilities.DataAccess.find_attacker/2 instead

  ## Parameters
    - killmail: The KillmailData struct
    - character_id: The character ID to find

  ## Returns
    - The attacker map if found, nil otherwise
  """
  @spec find_attacker(KillmailData.t(), integer() | String.t()) :: map() | nil
  def find_attacker(%KillmailData{} = killmail, character_id) do
    Logger.warning("Using deprecated DataAccess.find_attacker/2, please update your code")

    case convert_to_new_format(killmail) do
      {:ok, new_data} -> NewDataAccess.find_attacker(new_data, character_id)
      {:error, _} -> fallback_find_attacker(killmail, character_id)
    end
  end

  # Fallback implementation
  defp fallback_find_attacker(%KillmailData{attackers: attackers}, character_id) when is_list(attackers) do
    character_id_str = to_string(character_id)

    Enum.find(attackers, fn attacker ->
      attacker_id = Map.get(attacker, "character_id")
      to_string(attacker_id) == character_id_str
    end)
  end

  defp fallback_find_attacker(_, _), do: nil

  @doc """
  Determine if a character is involved in a killmail and their role.
  @deprecated Use WandererNotifier.Killmail.Utilities.DataAccess.character_involvement/2 instead

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
    Logger.warning("Using deprecated DataAccess.character_involvement/2, please update your code")

    case convert_to_new_format(killmail) do
      {:ok, new_data} -> NewDataAccess.character_involvement(new_data, character_id)
      {:error, _} -> fallback_character_involvement(killmail, character_id)
    end
  end

  # Fallback implementation
  defp fallback_character_involvement(%KillmailData{} = killmail, character_id) do
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
      attacker = fallback_find_attacker(killmail, character_id)
      if attacker, do: {:attacker, attacker}, else: nil
    end
  end

  @doc """
  Get all character IDs involved in a killmail.
  @deprecated Use WandererNotifier.Killmail.Utilities.DataAccess.all_character_ids/1 instead

  ## Parameters
    - killmail: The KillmailData struct

  ## Returns
    - List of character IDs (victim + all attackers)
  """
  @spec all_character_ids(KillmailData.t()) :: list(integer())
  def all_character_ids(%KillmailData{} = killmail) do
    Logger.warning("Using deprecated DataAccess.all_character_ids/1, please update your code")

    case convert_to_new_format(killmail) do
      {:ok, new_data} -> NewDataAccess.all_character_ids(new_data)
      {:error, _} -> fallback_all_character_ids(killmail)
    end
  end

  # Fallback implementation
  defp fallback_all_character_ids(%KillmailData{} = killmail) do
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
  @deprecated Use WandererNotifier.Killmail.Utilities.DataAccess.summary/1 instead

  ## Parameters
    - killmail: The KillmailData struct

  ## Returns
    - String with killmail summary
  """
  @spec summary(KillmailData.t()) :: String.t()
  def summary(%KillmailData{} = killmail) do
    Logger.warning("Using deprecated DataAccess.summary/1, please update your code")

    case convert_to_new_format(killmail) do
      {:ok, new_data} -> NewDataAccess.summary(new_data)
      {:error, _} -> fallback_summary(killmail)
    end
  end

  # Fallback implementation
  defp fallback_summary(%KillmailData{} = killmail) do
    victim_name = killmail.victim_name || "Unknown"
    victim_ship = killmail.victim_ship_name || "Unknown Ship"
    system_name = killmail.solar_system_name || "Unknown System"

    "Killmail ##{killmail.killmail_id}: #{victim_name} lost a #{victim_ship} in #{system_name}"
  end

  # Helper function to convert from old format to new format
  defp convert_to_new_format(%KillmailData{} = old_data) do
    # Check if it's already the new format
    if Map.has_key?(old_data, :__struct__) and old_data.__struct__ == Data do
      {:ok, old_data}
    else
      # Extract data from the old format to create a new Data struct
      attrs = Map.from_struct(old_data)

      case Data.from_map(attrs) do
        {:ok, new_data} -> {:ok, new_data}
        error -> error
      end
    end
  rescue
    e ->
      Logger.error("Error converting KillmailData: #{inspect(e)}")
      {:error, :conversion_error}
  end
end
