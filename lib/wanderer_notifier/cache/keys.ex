defmodule WandererNotifier.Cache.Keys do
  @moduledoc """
  Module for generating and validating cache keys.
  Provides functions for creating standardized cache keys for various data types.

  This module provides functions for generating and validating cache keys,
  ensuring consistent naming conventions across the application.

  Key Format: `prefix:entity_type:id` or `prefix:name`
  Examples:
    - `map:system:12345`
    - `tracked:character:98765`
    - `recent:kills`
  """

  # Key prefixes
  # For mapping data (systems, characters)
  @prefix_map "map"
  # For tracked entities
  @prefix_tracked "tracked"
  # For ESI API data
  @prefix_esi "esi"
  # For zKillboard data
  @prefix_zkill "zkill"
  # For recent/list data
  @prefix_recent "recent"
  # For existence checks
  @prefix_exists "exists"
  # For application state
  @prefix_state "state"
  # For configuration
  @prefix_config "config"
  # For critical application data
  @prefix_critical "critical"
  # For array data
  @prefix_array "array"
  # For list data
  @prefix_list "list"
  # For general data
  @prefix_data "data"

  # Entity types
  @entity_system "system"
  @entity_character "character"
  @entity_killmail "killmail"
  @entity_kills "kills"
  @entity_corporation "corporation"
  @entity_alliance "alliance"

  # Separator
  @separator ":"

  @doc """
  Generates a cache key for system data.

  ## Examples
      iex> WandererNotifier.Cache.Keys.system(30004759)
      "map:system:30004759"
  """
  @spec system(integer() | String.t()) :: String.t()
  def system(id) when is_integer(id) or is_binary(id) do
    join_parts([@prefix_map, @entity_system, to_string(id)])
  end

  @doc """
  Generates a cache key for character data.

  ## Examples
      iex> WandererNotifier.Cache.Keys.character(12345)
      "map:character:12345"
  """
  @spec character(integer() | String.t()) :: String.t()
  def character(nil) do
    require Logger
    Logger.warning("Cache.Keys.character/1 called with nil")
    nil
  end
  def character(character_id) when is_integer(character_id) or is_binary(character_id) do
    join_parts([@prefix_esi, @entity_character, to_string(character_id)])
  end
  def character(other) do
    require Logger
    Logger.warning("Cache.Keys.character/1 called with unexpected value: #{inspect(other)}")
    nil
  end

  @doc """
  Generates a cache key for a tracked system.

  ## Examples
      iex> WandererNotifier.Cache.Keys.tracked_system(30004759)
      "tracked:system:30004759"
  """
  @spec tracked_system(integer() | String.t()) :: String.t()
  def tracked_system(id) when is_integer(id) or is_binary(id) do
    join_parts([@prefix_tracked, @entity_system, to_string(id)])
  end

  @doc """
  Generates a cache key for a tracked character.

  ## Examples
      iex> WandererNotifier.Cache.Keys.tracked_character(12345)
      "tracked:character:12345"
  """
  @spec tracked_character(integer() | String.t()) :: String.t()
  def tracked_character(id) when is_integer(id) or is_binary(id) do
    "tracked_character:#{id}"
  end

  def tracked_character(id) when is_map(id) or is_struct(id) do
    require Logger
    Logger.error("[Cache.Keys] tracked_character/1 called with a map or struct!", value: inspect(id))
    raise ArgumentError, "Cache.Keys.tracked_character/1 called with a map or struct: #{inspect(id)}"
  end

  @doc """
  Generates a cache key for ESI killmail data.

  ## Examples
      iex> WandererNotifier.Cache.Keys.esi_killmail(12345)
      "esi:killmail:12345"
  """
  @spec esi_killmail(integer() | String.t()) :: String.t()
  def esi_killmail(id) when is_integer(id) or is_binary(id) do
    join_parts([@prefix_esi, @entity_killmail, to_string(id)])
  end

  @doc """
  Generates a cache key for recent kills.

  ## Examples
      iex> WandererNotifier.Cache.Keys.recent_kills()
      "recent:kills"
  """
  @spec recent_kills() :: String.t()
  def recent_kills do
    join_parts([@prefix_recent, @entity_kills])
  end

  @doc """
  Generates a cache key for checking if a killmail exists.

  ## Examples
      iex> WandererNotifier.Cache.Keys.killmail_exists(12345, 67890, "victim")
      "exists:killmail:12345:67890:victim"
  """
  @spec killmail_exists(integer() | String.t(), integer() | String.t(), String.t()) :: String.t()
  def killmail_exists(killmail_id, character_id, role)
      when (is_integer(killmail_id) or is_binary(killmail_id)) and
             (is_integer(character_id) or is_binary(character_id)) and
             is_binary(role) do
    join_parts([
      @prefix_exists,
      @entity_killmail,
      to_string(killmail_id),
      to_string(character_id),
      role
    ])
  end

  @doc """
  Generates a cache key for a character's recent kills.

  ## Examples
      iex> WandererNotifier.Cache.Keys.character_recent_kills(12345)
      "character:12345:recent_kills"
  """
  @spec character_recent_kills(integer() | String.t()) :: String.t()
  def character_recent_kills(character_id)
      when is_integer(character_id) or is_binary(character_id) do
    join_parts([@entity_character, to_string(character_id), "recent_kills"])
  end

  @doc """
  Generates a cache key for the character list.

  ## Examples
      iex> WandererNotifier.Cache.Keys.character_list()
      "map:characters"
  """
  @spec character_list() :: String.t()
  def character_list do
    join_parts([@prefix_map, "characters"])
  end

  @doc """
  Generates a cache key for kill comparison data.

  ## Examples
      iex> WandererNotifier.Cache.Keys.kill_comparison("daily", "date=2023-05-01")
      "kill_comparison:daily:date=2023-05-01"
  """
  @spec kill_comparison(String.t(), String.t()) :: String.t()
  def kill_comparison(type, params) when is_binary(type) and is_binary(params) do
    join_parts(["kill_comparison", type, params])
  end

  @doc """
  Generates a cache key for zkill recent kills.

  ## Examples
      iex> WandererNotifier.Cache.Keys.zkill_recent_kills()
      "zkill:recent_kills"
  """
  @spec zkill_recent_kills() :: String.t()
  def zkill_recent_kills do
    join_parts([@prefix_zkill, "recent_kills"])
  end

  @doc """
  Generates a cache key for the tracked systems list.

  ## Examples
      iex> WandererNotifier.Cache.Keys.tracked_systems_list()
      "tracked:systems"
  """
  @spec tracked_systems_list() :: String.t()
  def tracked_systems_list do
    join_parts([@prefix_tracked, "systems"])
  end

  @doc """
  Generates a cache key for the tracked characters list.

  ## Examples
      iex> WandererNotifier.Cache.Keys.tracked_characters_list()
      "tracked:characters"
  """
  @spec tracked_characters_list() :: String.t()
  def tracked_characters_list do
    join_parts([@prefix_tracked, "characters"])
  end

  @doc """
  Generates a cache key for the map systems list.

  ## Examples
      iex> WandererNotifier.Cache.Keys.map_systems()
      "map:systems"
  """
  @spec map_systems() :: String.t()
  def map_systems do
    join_parts([@prefix_map, "systems"])
  end

  @doc """
  Generates a cache key for the map system IDs list.

  ## Examples
      iex> WandererNotifier.Cache.Keys.map_system_ids()
      "map:system_ids"
  """
  @spec map_system_ids() :: String.t()
  def map_system_ids do
    join_parts([@prefix_map, "system_ids"])
  end

  @doc """
  Generates a cache key for the critical startup data.

  ## Examples
      iex> WandererNotifier.Cache.Keys.critical_startup_data()
      "critical:startup_data"
  """
  @spec critical_startup_data() :: String.t()
  def critical_startup_data do
    join_parts([@prefix_critical, "startup_data"])
  end

  @doc """
  Generates a cache key for the systems array.

  ## Examples
      iex> WandererNotifier.Cache.Keys.systems_array()
      "array:systems"
  """
  @spec systems_array() :: String.t()
  def systems_array do
    join_parts([@prefix_array, "systems"])
  end

  @doc """
  Generates a cache key for the killmails array.

  ## Examples
      iex> WandererNotifier.Cache.Keys.killmails_array()
      "array:killmails"
  """
  @spec killmails_array() :: String.t()
  def killmails_array do
    join_parts([@prefix_array, "killmails"])
  end

  @doc """
  Generates a cache key for the recent killmails list.

  ## Examples
      iex> WandererNotifier.Cache.Keys.recent_killmails_list()
      "list:recent_killmails"
  """
  @spec recent_killmails_list() :: String.t()
  def recent_killmails_list do
    join_parts([@prefix_list, "recent_killmails"])
  end

  @doc """
  Generates a cache key for the application state.

  ## Examples
      iex> WandererNotifier.Cache.Keys.application_state()
      "state:application"
  """
  @spec application_state() :: String.t()
  def application_state do
    join_parts([@prefix_state, "application"])
  end

  @doc """
  Generates a cache key for configuration.

  ## Examples
      iex> WandererNotifier.Cache.Keys.config("websocket")
      "config:websocket"
  """
  @spec config(String.t()) :: String.t()
  def config(name) when is_binary(name) do
    join_parts([@prefix_config, name])
  end

  @doc """
  Generates a cache key for zkill data.

  ## Examples
      iex> WandererNotifier.Cache.Keys.zkill_data("characterID", 12345)
      "zkill:characterID:12345"
  """
  @spec zkill_data(String.t(), integer() | String.t()) :: String.t()
  def zkill_data(type, id) when is_binary(type) and (is_integer(id) or is_binary(id)) do
    join_parts([@prefix_zkill, type, to_string(id)])
  end

  @doc """
  Generates a cache key for ESI data.

  ## Examples
      iex> WandererNotifier.Cache.Keys.esi_data("character", 12345)
      "esi:character:12345"
  """
  @spec esi_data(String.t(), integer() | String.t()) :: String.t()
  def esi_data(type, id) when is_binary(type) and (is_integer(id) or is_binary(id)) do
    join_parts([@prefix_esi, type, to_string(id)])
  end

  @doc """
  Generates a cache key for general data.

  ## Examples
      iex> WandererNotifier.Cache.Keys.data("some_key")
      "data:some_key"
  """
  @spec data(String.t()) :: String.t()
  def data(key) when is_binary(key) do
    join_parts([@prefix_data, key])
  end

  @doc """
  Validates if a key follows the standard pattern.

  ## Parameters
    - key: The cache key to validate

  ## Returns
    - true if key is valid
    - false if key is not valid

  ## Examples
      iex> WandererNotifier.Cache.Keys.valid?("map:system:12345")
      true

      iex> WandererNotifier.Cache.Keys.valid?("invalid-key")
      false
  """
  @spec valid?(String.t()) :: boolean()
  def valid?(key) when is_binary(key) do
    # Pattern: at least one segment with a separator
    # Must have at least two parts
    String.contains?(key, @separator) &&
      length(String.split(key, @separator)) >= 2
  end

  def valid?(_), do: false

  @doc """
  Extracts components from a key based on a pattern.

  ## Parameters
    - key: The cache key to extract from
    - pattern: The pattern to match against

  ## Returns
    - List of extracted components if successful
    - Empty list if no match

  ## Examples
      iex> WandererNotifier.Cache.Keys.extract_pattern("map:system:12345", "map:system:*")
      ["12345"]

      iex> WandererNotifier.Cache.Keys.extract_pattern("map:character:98765", "map:*:*")
      ["character", "98765"]
  """
  @spec extract_pattern(String.t(), String.t()) :: list(String.t())
  def extract_pattern(key, pattern) when is_binary(key) and is_binary(pattern) do
    key_parts = String.split(key, @separator)
    pattern_parts = String.split(pattern, @separator)

    # Only continue if the parts match in length
    if length(key_parts) == length(pattern_parts) do
      extract_matching_parts(key_parts, pattern_parts, [])
    else
      []
    end
  end

  def extract_pattern(_, _), do: []

  # Helper function to extract matching parts
  defp extract_matching_parts([], [], acc), do: Enum.reverse(acc)

  defp extract_matching_parts([key_part | key_rest], ["*" | pattern_rest], acc) do
    # Wildcard matches any value, so add the key part to accumulator
    extract_matching_parts(key_rest, pattern_rest, [key_part | acc])
  end

  defp extract_matching_parts([key_part | key_rest], [pattern_part | pattern_rest], acc) do
    # Check if the parts match exactly
    if key_part == pattern_part do
      extract_matching_parts(key_rest, pattern_rest, acc)
    else
      # Pattern doesn't match
      []
    end
  end

  @doc """
  Returns detailed information about a cache key.

  ## Parameters
    - key: The cache key to analyze

  ## Returns
    - Map with key details if valid
    - {:error, :invalid_key} if invalid

  ## Examples
      iex> WandererNotifier.Cache.Keys.map_key_info("map:system:12345")
      %{
        prefix: "map",
        entity_type: "system",
        id: "12345",
        parts: ["map", "system", "12345"]
      }
  """
  @spec map_key_info(String.t()) :: map() | {:error, :invalid_key}
  def map_key_info(key) when is_binary(key) do
    if valid?(key) do
      parts = String.split(key, @separator)

      case parts do
        # Standard format: prefix:entity_type:id
        [prefix, entity_type, id | rest] ->
          %{
            prefix: prefix,
            entity_type: entity_type,
            id: id,
            parts: parts,
            extra: rest
          }

        # Simple format: prefix:name
        [prefix, name] ->
          %{
            prefix: prefix,
            name: name,
            parts: parts
          }

        _ ->
          %{
            parts: parts
          }
      end
    else
      {:error, :invalid_key}
    end
  end

  def map_key_info(_), do: {:error, :invalid_key}

  # Private helper function to join parts with separator
  defp join_parts(parts) when is_list(parts) do
    Enum.join(parts, @separator)
  end

  @doc """
  Generates a cache key for tracked systems.

  ## Examples
      iex> WandererNotifier.Cache.Keys.tracked_systems()
      "tracked:systems"
  """
  @spec tracked_systems() :: String.t()
  def tracked_systems do
    tracked_systems_list()
  end

  @doc """
  Generates a cache key for a killmail.

  ## Examples
      iex> WandererNotifier.Cache.Keys.killmail(12345, "abc123")
      "esi:killmail:12345:abc123"
  """
  @spec killmail(integer() | String.t(), String.t()) :: String.t()
  def killmail(kill_id, killmail_hash)
      when (is_integer(kill_id) or is_binary(kill_id)) and is_binary(killmail_hash) do
    join_parts([@prefix_esi, @entity_killmail, to_string(kill_id), killmail_hash])
  end

  @doc """
  Generates a cache key for a corporation.

  ## Examples
      iex> WandererNotifier.Cache.Keys.corporation(12345)
      "esi:corporation:12345"
  """
  @spec corporation(integer() | String.t()) :: String.t()
  def corporation(corporation_id) when is_integer(corporation_id) or is_binary(corporation_id) do
    join_parts([@prefix_esi, @entity_corporation, to_string(corporation_id)])
  end

  @doc """
  Generates a cache key for an alliance.

  ## Examples
      iex> WandererNotifier.Cache.Keys.alliance(12345)
      "esi:alliance:12345"
  """
  @spec alliance(integer() | String.t()) :: String.t()
  def alliance(alliance_id) when is_integer(alliance_id) or is_binary(alliance_id) do
    join_parts([@prefix_esi, @entity_alliance, to_string(alliance_id)])
  end

  @spec alliance(integer() | String.t()) :: String.t() | nil
  def alliance(nil), do: nil

  @doc """
  Generates a cache key for a ship type.

  ## Examples
      iex> WandererNotifier.Cache.Keys.ship_type(12345)
      "esi:ship_type:12345"
  """
  @spec ship_type(integer() | String.t()) :: String.t()
  def ship_type(ship_type_id) when is_integer(ship_type_id) or is_binary(ship_type_id) do
    join_parts([@prefix_esi, "ship_type", to_string(ship_type_id)])
  end

  @doc """
  Returns the cache key for a system.
  """
  def system_key(system_id) when is_integer(system_id), do: system(system_id)

end
