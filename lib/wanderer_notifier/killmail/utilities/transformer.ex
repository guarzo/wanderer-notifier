defmodule WandererNotifier.Killmail.Utilities.Transformer do
  @moduledoc """
  Transformer module for killmail data conversion.

  This module provides functions to convert between different killmail data
  formats, ensuring consistent transformation at well-defined points in the
  pipeline. It centralizes conversion logic to reduce duplication and
  inconsistencies.
  """

  alias WandererNotifier.Killmail.Utilities.DataAccess
  alias WandererNotifier.Killmail.Core.Data
  alias WandererNotifier.Killmail.Core.Validator
  alias WandererNotifier.Resources.Killmail, as: KillmailResource

  @doc """
  Converts any killmail format to a Data struct.

  This is the primary entry point for standardizing killmail data formats.
  Use this function whenever you need to ensure you're working with a
  consistent killmail representation.

  ## Parameters
    - killmail: Any supported killmail format (map, KillmailResource, etc.)

  ## Returns
    - %Data{} struct with standardized fields
  """
  def to_killmail_data(killmail)

  # Already a Data struct, just return it
  def to_killmail_data(%Data{} = killmail), do: killmail

  # Convert KillmailResource to Data
  def to_killmail_data(%KillmailResource{} = resource) do
    Data.from_resource(resource)
  end

  # Convert raw data to Data
  def to_killmail_data(data) when is_map(data) do
    # Extract core data directly
    killmail_id = extract_killmail_id(data)
    system_id = extract_system_id(data)
    system_name = extract_system_name(data)
    kill_time = extract_kill_time(data)
    zkb_data = extract_zkb_data(data)
    victim_data = extract_victim(data)
    attackers = extract_attackers(data)

    # Extract victim data directly
    victim_id = extract_victim_id(victim_data)
    victim_name = extract_victim_name(victim_data)
    victim_ship_id = extract_victim_ship_id(victim_data)
    victim_ship_name = extract_victim_ship_name(victim_data)

    # Build a standardized Data struct using the Data.from_map function
    Data.from_map(%{
      killmail_id: killmail_id,
      solar_system_id: system_id,
      solar_system_name: system_name,
      kill_time: kill_time,
      raw_zkb_data: zkb_data,

      # Victim data
      victim_id: victim_id,
      victim_name: victim_name,
      victim_ship_id: victim_ship_id,
      victim_ship_name: victim_ship_name,

      # Attacker information
      attackers: attackers,
      persisted: Map.get(data, :persisted, false),
      metadata: Map.get(data, :metadata, %{})
    })
  end

  # Default for nil or non-map values
  def to_killmail_data(nil), do: {:error, :nil_input}
  def to_killmail_data(_), do: {:error, :invalid_input_type}

  @doc """
  Converts a killmail to the normalized format expected by the database.

  This function transforms a killmail into a normalized map format suitable
  for database persistence, extracting essential fields.

  ## Parameters
    - killmail: Any supported killmail format

  ## Returns
    - Map with normalized fields ready for database persistence
  """
  def to_normalized_format(killmail) do
    # First ensure we have a standardized killmail format
    case to_killmail_data(killmail) do
      {:ok, killmail_data} ->
        # Then normalize the data
        %{
          killmail_id: killmail_data.killmail_id,
          zkb_hash: killmail_data.zkb_hash,
          kill_time: killmail_data.kill_time,
          solar_system_id: killmail_data.solar_system_id,
          solar_system_name: killmail_data.solar_system_name,
          region_id: killmail_data.region_id,
          region_name: killmail_data.region_name,
          victim_id: killmail_data.victim_id,
          victim_name: killmail_data.victim_name,
          victim_ship_id: killmail_data.victim_ship_id,
          victim_ship_name: killmail_data.victim_ship_name,
          total_value: killmail_data.total_value,
          points: killmail_data.points,
          is_npc: killmail_data.is_npc,
          is_solo: killmail_data.is_solo
        }

      %Data{} = killmail_data ->
        # Handle direct Data struct
        %{
          killmail_id: killmail_data.killmail_id,
          zkb_hash: killmail_data.zkb_hash,
          kill_time: killmail_data.kill_time,
          solar_system_id: killmail_data.solar_system_id,
          solar_system_name: killmail_data.solar_system_name,
          region_id: killmail_data.region_id,
          region_name: killmail_data.region_name,
          victim_id: killmail_data.victim_id,
          victim_name: killmail_data.victim_name,
          victim_ship_id: killmail_data.victim_ship_id,
          victim_ship_name: killmail_data.victim_ship_name,
          total_value: killmail_data.total_value,
          points: killmail_data.points,
          is_npc: killmail_data.is_npc,
          is_solo: killmail_data.is_solo
        }

      _ ->
        %{}
    end
  end

  # Direct extraction functions to replace Extractor calls
  # These are private and only used within this module

  defp extract_killmail_id(data) do
    cond do
      is_map(data) && Map.has_key?(data, :killmail_id) ->
        data.killmail_id

      is_map(data) && Map.has_key?(data, "killmail_id") ->
        data["killmail_id"]

      is_map(data) && Map.has_key?(data, "zkb") && is_map(data["zkb"]) &&
          Map.has_key?(data["zkb"], "killmail_id") ->
        data["zkb"]["killmail_id"]

      true ->
        nil
    end
  end

  defp extract_system_id(data) do
    cond do
      is_map(data) && Map.has_key?(data, :solar_system_id) ->
        data.solar_system_id

      is_map(data) && Map.has_key?(data, "solar_system_id") ->
        data["solar_system_id"]

      is_map(data) && Map.has_key?(data, :esi_data) && is_map(data.esi_data) &&
          Map.has_key?(data.esi_data, "solar_system_id") ->
        data.esi_data["solar_system_id"]

      is_map(data) && Map.has_key?(data, "esi_data") && is_map(data["esi_data"]) &&
          Map.has_key?(data["esi_data"], "solar_system_id") ->
        data["esi_data"]["solar_system_id"]

      true ->
        nil
    end
  end

  defp extract_system_name(data) do
    cond do
      is_map(data) && Map.has_key?(data, :solar_system_name) ->
        data.solar_system_name

      is_map(data) && Map.has_key?(data, "solar_system_name") ->
        data["solar_system_name"]

      is_map(data) && Map.has_key?(data, :esi_data) && is_map(data.esi_data) &&
          Map.has_key?(data.esi_data, "solar_system_name") ->
        data.esi_data["solar_system_name"]

      is_map(data) && Map.has_key?(data, "esi_data") && is_map(data["esi_data"]) &&
          Map.has_key?(data["esi_data"], "solar_system_name") ->
        data["esi_data"]["solar_system_name"]

      true ->
        nil
    end
  end

  defp extract_kill_time(data) do
    time =
      cond do
        is_map(data) && Map.has_key?(data, :kill_time) ->
          data.kill_time

        is_map(data) && Map.has_key?(data, "kill_time") ->
          data["kill_time"]

        is_map(data) && Map.has_key?(data, :esi_data) && is_map(data.esi_data) &&
            Map.has_key?(data.esi_data, "killmail_time") ->
          data.esi_data["killmail_time"]

        is_map(data) && Map.has_key?(data, "esi_data") && is_map(data["esi_data"]) &&
            Map.has_key?(data["esi_data"], "killmail_time") ->
          data["esi_data"]["killmail_time"]

        true ->
          nil
      end

    # Handle string timestamps
    if is_binary(time) do
      case DateTime.from_iso8601(time) do
        {:ok, datetime, _} -> datetime
        _ -> nil
      end
    else
      time
    end
  end

  defp extract_zkb_data(data) do
    cond do
      is_map(data) && Map.has_key?(data, :zkb_data) -> data.zkb_data
      is_map(data) && Map.has_key?(data, "zkb_data") -> data["zkb_data"]
      is_map(data) && Map.has_key?(data, :zkb) -> data.zkb
      is_map(data) && Map.has_key?(data, "zkb") -> data["zkb"]
      true -> %{}
    end
  end

  defp extract_victim(data) do
    cond do
      is_map(data) && Map.has_key?(data, :victim) ->
        data.victim

      is_map(data) && Map.has_key?(data, "victim") ->
        data["victim"]

      is_map(data) && Map.has_key?(data, :esi_data) && is_map(data.esi_data) &&
          Map.has_key?(data.esi_data, "victim") ->
        data.esi_data["victim"]

      is_map(data) && Map.has_key?(data, "esi_data") && is_map(data["esi_data"]) &&
          Map.has_key?(data["esi_data"], "victim") ->
        data["esi_data"]["victim"]

      true ->
        %{}
    end
  end

  defp extract_attackers(data) do
    cond do
      is_map(data) && Map.has_key?(data, :attackers) ->
        data.attackers

      is_map(data) && Map.has_key?(data, "attackers") ->
        data["attackers"]

      is_map(data) && Map.has_key?(data, :esi_data) && is_map(data.esi_data) &&
          Map.has_key?(data.esi_data, "attackers") ->
        data.esi_data["attackers"]

      is_map(data) && Map.has_key?(data, "esi_data") && is_map(data["esi_data"]) &&
          Map.has_key?(data["esi_data"], "attackers") ->
        data["esi_data"]["attackers"]

      true ->
        []
    end
  end

  defp extract_victim_id(victim) when is_map(victim) do
    Map.get(victim, "character_id") || Map.get(victim, :character_id)
  end

  defp extract_victim_id(_), do: nil

  defp extract_victim_name(victim) when is_map(victim) do
    Map.get(victim, "character_name") || Map.get(victim, :character_name)
  end

  defp extract_victim_name(_), do: nil

  defp extract_victim_ship_id(victim) when is_map(victim) do
    Map.get(victim, "ship_type_id") || Map.get(victim, :ship_type_id)
  end

  defp extract_victim_ship_id(_), do: nil

  defp extract_victim_ship_name(victim) when is_map(victim) do
    Map.get(victim, "ship_type_name") || Map.get(victim, :ship_type_name)
  end

  defp extract_victim_ship_name(_), do: nil
end
