defmodule WandererNotifier.Cache.Keys do
  @moduledoc """
  Centralized cache key management.

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
  Validates if a cache key follows the established patterns.

  ## Examples
      iex> WandererNotifier.Cache.Keys.valid?("map:system:12345")
      true

      iex> WandererNotifier.Cache.Keys.valid?("invalid-key")
      false
  """
  @spec valid?(String.t()) :: boolean()
  def valid?(key) when is_binary(key) do
    cond do
      # Check for prefix:entity:id pattern
      String.match?(key, ~r/^[\w\-]+:[\w\-]+:\d+$/) -> true
      # Check for prefix:name pattern
      String.match?(key, ~r/^[\w\-]+:[\w\-]+$/) -> true
      # Check for more complex patterns with multiple separators
      String.match?(key, ~r/^[\w\-]+:[\w\-]+:[\w\-]+:[\w\-]+$/) -> true
      String.match?(key, ~r/^[\w\-]+:[\w\-]+:[\w\-]+:[\w\-]+:[\w\-]+$/) -> true
      # Default to false for unexpected patterns
      true -> false
    end
  end

  @doc """
  Extracts the key pattern for grouping similar cache keys.

  ## Examples
      iex> WandererNotifier.Cache.Keys.extract_pattern("map:system:12345")
      "map:system"
  """
  @spec extract_pattern(String.t()) :: String.t()
  def extract_pattern(key) when is_binary(key) do
    cond do
      # For keys with IDs embedded, extract the pattern part
      String.match?(key, ~r/^[\w\-]+:[\w\-]+:\d+$/) ->
        # Pattern for keys like "map:system:12345" -> "map:system"
        key |> String.split(@separator) |> Enum.take(2) |> Enum.join(@separator)

      # For other known key formats
      String.match?(key, ~r/^[\w\-]+:[\w\-]+$/) ->
        # Keys like "map:systems" -> return as is
        key

      # Match most prefixes
      true ->
        # Try to get the prefix part
        case String.split(key, @separator, parts: 2) do
          [prefix, _] -> "#{prefix}:*"
          _ -> key
        end
    end
  end

  @doc """
  Determines if a key is for an array type.
  """
  @spec is_array_key?(String.t()) :: boolean()
  def is_array_key?(key) when is_binary(key) do
    String.starts_with?(key, @prefix_array <> @separator) ||
      String.starts_with?(key, @prefix_list <> @separator) ||
      String.starts_with?(key, @prefix_recent <> @separator)
  end

  @doc """
  Determines if a key is for a map type.
  """
  @spec is_map_key?(String.t()) :: boolean()
  def is_map_key?(key) when is_binary(key) do
    String.starts_with?(key, @prefix_map <> @separator) ||
      String.starts_with?(key, @prefix_data <> @separator) ||
      String.starts_with?(key, @prefix_config <> @separator)
  end

  @doc """
  Determines if a key is for a critical component.
  """
  @spec is_critical_key?(String.t()) :: boolean()
  def is_critical_key?(key) when is_binary(key) do
    String.starts_with?(key, @prefix_critical <> @separator) ||
      key in ["license_status", "core_config"]
  end

  @doc """
  Determines if a key is for application state.
  """
  @spec is_state_key?(String.t()) :: boolean()
  def is_state_key?(key) when is_binary(key) do
    String.starts_with?(key, @prefix_state <> @separator) ||
      String.starts_with?(key, "app" <> @separator) ||
      String.starts_with?(key, @prefix_config <> @separator)
  end

  @doc """
  Determines if a key is for static info.
  """
  @spec is_static_info_key?(String.t()) :: boolean()
  def is_static_info_key?(key) when is_binary(key) do
    String.ends_with?(key, "static_info")
  end

  # Helper to join parts with the separator
  defp join_parts(parts) when is_list(parts) do
    Enum.join(parts, @separator)
  end
end
