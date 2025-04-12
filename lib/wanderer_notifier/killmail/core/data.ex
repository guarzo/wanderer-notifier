defmodule WandererNotifier.Killmail.Core.Data do
  @moduledoc """
  Standardized struct for killmail data.

  This module provides a consistent structure for representing killmail data
  throughout the application. It defines a struct with all necessary fields and
  functions to convert between different data formats.
  """

  alias WandererNotifier.Logger.Logger, as: AppLogger

  @typedoc """
  Core killmail data structure with all required fields.
  """
  @type t :: %__MODULE__{
          # Core identifiers
          killmail_id: integer() | nil,
          zkb_hash: String.t() | nil,
          kill_time: DateTime.t() | nil,

          # System information
          solar_system_id: integer() | nil,
          solar_system_name: String.t() | nil,
          region_id: integer() | nil,
          region_name: String.t() | nil,

          # Victim information
          victim_id: integer() | nil,
          victim_name: String.t() | nil,
          victim_ship_id: integer() | nil,
          victim_ship_name: String.t() | nil,
          victim_corporation_id: integer() | nil,
          victim_corporation_name: String.t() | nil,

          # Attack information
          attackers: list(map()) | nil,
          attacker_count: integer() | nil,
          final_blow_attacker_id: integer() | nil,
          final_blow_attacker_name: String.t() | nil,
          final_blow_ship_id: integer() | nil,
          final_blow_ship_name: String.t() | nil,

          # Economic data
          total_value: float() | nil,
          points: integer() | nil,
          is_npc: boolean() | nil,
          is_solo: boolean() | nil,

          # Raw data for debugging and special cases
          raw_zkb_data: map() | nil,
          raw_esi_data: map() | nil,
          raw_data: map() | nil,

          # Processing metadata
          metadata: map(),
          persisted: boolean()
        }

  # Default values for struct fields
  defstruct killmail_id: nil,
            zkb_hash: nil,
            kill_time: nil,
            solar_system_id: nil,
            solar_system_name: nil,
            region_id: nil,
            region_name: nil,
            victim_id: nil,
            victim_name: nil,
            victim_ship_id: nil,
            victim_ship_name: nil,
            victim_corporation_id: nil,
            victim_corporation_name: nil,
            attackers: [],
            attacker_count: 0,
            final_blow_attacker_id: nil,
            final_blow_attacker_name: nil,
            final_blow_ship_id: nil,
            final_blow_ship_name: nil,
            total_value: nil,
            points: nil,
            is_npc: false,
            is_solo: false,
            raw_zkb_data: %{},
            raw_esi_data: %{},
            raw_data: %{},
            metadata: %{},
            persisted: false

  @doc """
  Creates a Data struct from ZKillboard and ESI data.

  This function takes raw data from ZKillboard and ESI and converts it into
  a standardized Data struct with all fields extracted to the top level.

  ## Parameters
    - zkb_data: Raw data from ZKillboard API
    - esi_data: Raw data from ESI API

  ## Returns
    - {:ok, data} with the created Data struct
    - {:error, reason} if conversion fails
  """
  @spec from_zkb_and_esi(map(), map()) :: {:ok, t()} | {:error, any()}
  def from_zkb_and_esi(zkb_data, esi_data) do
    try do
      # Extract ZKB-specific fields
      zkb_map = Map.get(zkb_data, "zkb", Map.get(zkb_data, :zkb, zkb_data))
      zkb_hash = Map.get(zkb_map, "hash", Map.get(zkb_map, :hash))
      total_value = Map.get(zkb_map, "totalValue", Map.get(zkb_map, :totalValue))
      points = Map.get(zkb_map, "points", Map.get(zkb_map, :points))
      is_npc = Map.get(zkb_map, "npc", Map.get(zkb_map, :npc, false))
      is_solo = Map.get(zkb_map, "solo", Map.get(zkb_map, :solo, false))

      # Extract killmail ID and time from ESI data
      killmail_id =
        Map.get(zkb_data, "killmail_id") ||
          Map.get(zkb_data, :killmail_id) ||
          Map.get(esi_data, "killmail_id") ||
          Map.get(esi_data, :killmail_id) ||
          Map.get(zkb_map, "killmail_id") ||
          Map.get(zkb_map, :killmail_id)

      kill_time =
        case Map.get(esi_data, "killmail_time", Map.get(esi_data, :killmail_time)) do
          nil -> nil
          time when is_binary(time) -> parse_datetime(time)
          time -> time
        end

      # Extract solar system information
      solar_system_id = Map.get(esi_data, "solar_system_id", Map.get(esi_data, :solar_system_id))

      solar_system_name =
        Map.get(esi_data, "solar_system_name", Map.get(esi_data, :solar_system_name))

      # Extract victim information
      victim_data = Map.get(esi_data, "victim", Map.get(esi_data, :victim, %{}))
      victim_id = Map.get(victim_data, "character_id", Map.get(victim_data, :character_id))
      victim_name = Map.get(victim_data, "character_name", Map.get(victim_data, :character_name))
      victim_ship_id = Map.get(victim_data, "ship_type_id", Map.get(victim_data, :ship_type_id))

      victim_corporation_id =
        Map.get(victim_data, "corporation_id", Map.get(victim_data, :corporation_id))

      # Extract attackers information
      attackers = Map.get(esi_data, "attackers", Map.get(esi_data, :attackers, []))

      # Find final blow attacker
      final_blow_attacker =
        Enum.find(attackers, fn attacker ->
          Map.get(attacker, "final_blow", Map.get(attacker, :final_blow, false)) == true
        end) || %{}

      # Create the Data struct
      data = %__MODULE__{
        killmail_id: killmail_id,
        zkb_hash: zkb_hash,
        kill_time: kill_time,
        solar_system_id: solar_system_id,
        solar_system_name: solar_system_name,
        region_id: Map.get(esi_data, "region_id", Map.get(esi_data, :region_id)),
        region_name: Map.get(esi_data, "region_name", Map.get(esi_data, :region_name)),
        victim_id: victim_id,
        victim_name: victim_name,
        victim_ship_id: victim_ship_id,
        victim_ship_name: Map.get(victim_data, "ship_name", Map.get(victim_data, :ship_name)),
        victim_corporation_id: victim_corporation_id,
        victim_corporation_name:
          Map.get(victim_data, "corporation_name", Map.get(victim_data, :corporation_name)),
        attackers: attackers,
        attacker_count: length(attackers),
        final_blow_attacker_id:
          Map.get(
            final_blow_attacker,
            "character_id",
            Map.get(final_blow_attacker, :character_id)
          ),
        final_blow_attacker_name:
          Map.get(final_blow_attacker, "name", Map.get(final_blow_attacker, :name)),
        final_blow_ship_id:
          Map.get(
            final_blow_attacker,
            "ship_type_id",
            Map.get(final_blow_attacker, :ship_type_id)
          ),
        final_blow_ship_name:
          Map.get(final_blow_attacker, "ship_name", Map.get(final_blow_attacker, :ship_name)),
        total_value: total_value,
        points: points,
        is_npc: is_npc,
        is_solo: is_solo,
        raw_zkb_data: zkb_map,
        raw_esi_data: esi_data
      }

      {:ok, data}
    rescue
      e ->
        AppLogger.kill_error("Error creating Data struct: #{Exception.message(e)}")
        {:error, {:data_conversion_error, Exception.message(e)}}
    end
  end

  @doc """
  Creates a Data struct from a database resource.

  This function takes a killmail database record and converts it into
  a standardized Data struct with all fields extracted to the top level.

  ## Parameters
    - resource: Database resource (KillmailResource struct or compatible map)

  ## Returns
    - {:ok, data} with the created Data struct
    - {:error, reason} if conversion fails
  """
  @spec from_resource(struct() | map()) :: {:ok, t()} | {:error, any()}
  def from_resource(resource) do
    try do
      # Extract fields from resource
      data = %__MODULE__{
        killmail_id: Map.get(resource, :killmail_id),
        zkb_hash: Map.get(resource, :zkb_hash),
        kill_time: Map.get(resource, :kill_time),
        solar_system_id: Map.get(resource, :solar_system_id),
        solar_system_name: Map.get(resource, :solar_system_name),
        region_id: Map.get(resource, :region_id),
        region_name: Map.get(resource, :region_name),
        victim_id: Map.get(resource, :victim_id),
        victim_name: Map.get(resource, :victim_name),
        victim_ship_id: Map.get(resource, :victim_ship_id),
        victim_ship_name: Map.get(resource, :victim_ship_name),
        victim_corporation_id: Map.get(resource, :victim_corporation_id),
        victim_corporation_name: Map.get(resource, :victim_corporation_name),
        attackers: Map.get(resource, :full_attacker_data, []),
        attacker_count: Map.get(resource, :attacker_count, 0),
        final_blow_attacker_id: Map.get(resource, :final_blow_attacker_id),
        final_blow_attacker_name: Map.get(resource, :final_blow_attacker_name),
        final_blow_ship_id: Map.get(resource, :final_blow_ship_id),
        final_blow_ship_name: Map.get(resource, :final_blow_ship_name),
        total_value: Map.get(resource, :total_value),
        points: Map.get(resource, :points),
        is_npc: Map.get(resource, :is_npc, false),
        is_solo: Map.get(resource, :is_solo, false),
        persisted: true
      }

      {:ok, data}
    rescue
      e ->
        AppLogger.kill_error("Error creating Data struct from resource: #{Exception.message(e)}")
        {:error, {:resource_conversion_error, Exception.message(e)}}
    end
  end

  @doc """
  Creates a Data struct from a generic map.

  This function takes a map with killmail data in any format and attempts
  to convert it into a standardized Data struct.

  ## Parameters
    - map: Map with killmail data

  ## Returns
    - {:ok, data} with the created Data struct
    - {:error, reason} if conversion fails
  """
  @spec from_map(map()) :: {:ok, t()} | {:error, any()}
  def from_map(map) when is_map(map) do
    try do
      # Check if the map has nested zkb and esi_data
      if Map.has_key?(map, "zkb") || Map.has_key?(map, :zkb_data) || Map.has_key?(map, "zkb_data") do
        # Extract zkb data
        zkb_data =
          map
          |> Map.get("zkb", Map.get(map, :zkb_data, Map.get(map, "zkb_data", %{})))

        # Extract esi data if available, otherwise use the map itself
        esi_data =
          map
          |> Map.get(:esi_data, Map.get(map, "esi_data", map))

        # Use from_zkb_and_esi
        from_zkb_and_esi(zkb_data, esi_data)
      else
        # Try to create directly from the map
        data = %__MODULE__{
          killmail_id:
            Map.get(map, :killmail_id) || Map.get(map, "killmail_id") ||
              Map.get(map, "killID") || Map.get(map, :killID),
          raw_data: map
        }

        {:ok, data}
      end
    rescue
      e ->
        AppLogger.kill_error("Error creating Data struct from map: #{Exception.message(e)}")
        {:error, {:map_conversion_error, Exception.message(e)}}
    end
  end

  def from_map(other) do
    {:error, {:invalid_data_type, "Expected map, got: #{inspect(other)}"}}
  end

  @doc """
  Merges data from two Data structs, preferring values from the second struct when they exist.

  ## Parameters
    - data: The base Data struct
    - other_data: The Data struct with values to merge in

  ## Returns
    - {:ok, data} with the merged Data struct
    - {:error, reason} if merging fails
  """
  @spec merge(t(), t()) :: {:ok, t()} | {:error, any()}
  def merge(%__MODULE__{} = data, %__MODULE__{} = other_data) do
    try do
      # Convert both structs to maps
      data_map = Map.from_struct(data)
      other_map = Map.from_struct(other_data)

      # Merge the maps, with other_data taking precedence
      merged_map =
        Enum.reduce(other_map, data_map, fn {key, value}, acc ->
          # Only update if the value is not nil and not an empty map/list
          case value do
            nil -> acc
            [] when is_list(value) -> acc
            %{} when value == %{} -> acc
            _ -> Map.put(acc, key, value)
          end
        end)

      # Create a new struct from the merged map
      {:ok, struct(__MODULE__, merged_map)}
    rescue
      e ->
        AppLogger.kill_error("Error merging Data structs: #{Exception.message(e)}")
        {:error, {:merge_error, Exception.message(e)}}
    end
  end

  def merge(%__MODULE__{} = data, other) do
    AppLogger.kill_error("Cannot merge Data with non-Data: #{inspect(other)}")
    {:error, {:invalid_merge_type, "Expected Data struct for merging"}}
  end

  def merge(other, _) do
    AppLogger.kill_error("Cannot merge non-Data with anything: #{inspect(other)}")
    {:error, {:invalid_merge_type, "Expected Data struct as base for merging"}}
  end

  # Parse datetime string to DateTime
  defp parse_datetime(datetime_str) when is_binary(datetime_str) do
    case DateTime.from_iso8601(datetime_str) do
      {:ok, datetime, _} -> datetime
      _ -> nil
    end
  end

  defp parse_datetime(datetime), do: datetime
end
