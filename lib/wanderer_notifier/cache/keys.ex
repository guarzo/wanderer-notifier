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
  @entity_region "region"

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
  def character(id) when is_integer(id) or is_binary(id) do
    join_parts([@prefix_map, @entity_character, to_string(id)])
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
    join_parts([@prefix_tracked, @entity_character, to_string(id)])
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
  Validates if a key follows the correct pattern.

  ## Examples
      iex> WandererNotifier.Cache.Keys.valid?("map:system:12345")
      true
      iex> WandererNotifier.Cache.Keys.valid?("invalid-key")
      false
  """
  @spec valid?(String.t()) :: boolean()
  def valid?(key) when is_binary(key) do
    key =~ ~r/^[a-z_]+:[a-z0-9_]+(?::[a-z0-9_]+)*$/
  end

  @doc """
  Extracts the pattern parts from a key.

  ## Examples
      iex> WandererNotifier.Cache.Keys.extract_pattern("map:system:12345")
      ["map", "system", "12345"]
  """
  @spec extract_pattern(String.t()) :: [String.t()]
  def extract_pattern(key) when is_binary(key) do
    String.split(key, @separator)
  end

  @doc """
  Extracts a map key prefix and entity type from a key.

  ## Examples
      iex> WandererNotifier.Cache.Keys.map_key_info("map:system:12345")
      {:ok, "system", "12345"}
      iex> WandererNotifier.Cache.Keys.map_key_info("invalid-key")
      {:error, :invalid_key}
  """
  @spec map_key_info(String.t()) :: {:ok, String.t(), String.t()} | {:error, :invalid_key}
  def map_key_info(key) when is_binary(key) do
    parts = extract_pattern(key)

    case parts do
      [@prefix_map, entity_type, id] -> {:ok, entity_type, id}
      _ -> {:error, :invalid_key}
    end
  end

  # Private helper function to join parts with separator
  defp join_parts(parts) when is_list(parts) do
    Enum.join(parts, @separator)
  end
end
