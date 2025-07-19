defmodule WandererNotifier.Infrastructure.Cache.Keys do
  @moduledoc """
  Module for generating and validating cache keys.
  Provides functions for creating standardized cache keys for various data types.

  Key Format: `prefix:entity_type:id` or `prefix:name`
  Examples:
    - `map:system:12345`
    - `tracked:character:98765`
    - `recent:kills`
  """

  import WandererNotifier.Infrastructure.Cache.KeyGenerator

  # Key prefixes
  @prefix_map "map"
  @prefix_tracked "tracked"
  @prefix_esi "esi"
  @prefix_zkill "zkill"
  @prefix_recent "recent"
  @prefix_exists "exists"
  @prefix_state "state"
  @prefix_config "config"
  @prefix_critical "critical"
  @prefix_array "array"
  @prefix_data "data"
  @prefix_dedup "dedup"

  # Entity types
  @entity_system "system"
  @entity_character "character"
  @entity_killmail "killmail"
  @entity_kills "kills"
  @entity_corporation "corporation"
  @entity_alliance "alliance"

  # Generate standard cache key functions using consolidated KeyGenerator
  defkey(:system, @prefix_map, @entity_system)
  defkey(:character, @prefix_esi, @entity_character)
  defkey(:tracked_system, @prefix_tracked, @entity_system)
  defkey(:tracked_character, @prefix_tracked, @entity_character)
  defkey(:esi_killmail, @prefix_esi, @entity_killmail)
  defkey(:corporation, @prefix_esi, @entity_corporation)
  defkey(:alliance, @prefix_esi, @entity_alliance)
  defkey(:ship_type, @prefix_esi, "ship_type")
  defkey(:type, @prefix_esi, "type")
  defkey(:dedup_system, @prefix_dedup, @entity_system)
  defkey(:dedup_character, @prefix_dedup, @entity_character)
  defkey(:dedup_kill, @prefix_dedup, @entity_killmail)

  # Simple prefix-based keys using consolidated KeyGenerator
  defkey_simple(:map_systems, @prefix_map, "systems")
  defkey_simple(:map_system_ids, @prefix_map, "system_ids")
  defkey_simple(:critical_startup_data, @prefix_critical, "startup_data")
  defkey_simple(:systems_array, @prefix_array, "systems")
  defkey_simple(:killmails_array, @prefix_array, "killmails")
  defkey_simple(:recent_killmails_list, @prefix_recent, @entity_kills)
  defkey_simple(:application_state, @prefix_state, "application")
  defkey_simple(:character_list, @prefix_map, "characters")
  defkey_simple(:tracked_systems_list, @prefix_tracked, "systems")
  defkey_simple(:system_list, @prefix_map, "systems")
  defkey_simple(:zkill_recent_kills, @prefix_zkill, "recent_kills")

  # Special case functions that don't fit the standard pattern
  @doc "Key for a killmail with hash"
  @spec killmail(integer() | String.t(), integer() | String.t(), String.t() | nil) :: String.t()
  def killmail(kill_id, killmail_hash, extra \\ nil),
    do: combine([@prefix_esi, @entity_killmail], [kill_id, killmail_hash], extra)

  @doc "Key for arbitrary data"
  @spec data(String.t(), String.t() | nil) :: String.t()
  def data(key, extra \\ nil),
    do: combine([@prefix_data], [key], extra)

  @doc "Key for zKillboard data by type and id"
  @spec zkill_data(String.t(), integer() | String.t(), String.t() | nil) :: String.t()
  def zkill_data(type, id, extra \\ nil),
    do: combine([@prefix_zkill], [type, id], extra)

  @doc "Key for ESI data by type and id"
  @spec esi_data(String.t(), integer() | String.t(), String.t() | nil) :: String.t()
  def esi_data(type, id, extra \\ nil),
    do: combine([@prefix_esi], [type, id], extra)

  @doc """
  Generates a cache key for checking if a killmail exists.
  """
  @spec killmail_exists(integer() | String.t(), integer() | String.t(), String.t()) :: String.t()
  def killmail_exists(killmail_id, character_id, role)
      when (is_integer(killmail_id) or is_binary(killmail_id)) and
             (is_integer(character_id) or is_binary(character_id)) and
             is_binary(role) do
    combine([@prefix_exists, @entity_killmail], [killmail_id, character_id, role], nil)
  end

  @doc "Key for a character's recent kills"
  @spec character_recent_kills(integer() | String.t()) :: String.t()
  def character_recent_kills(character_id) do
    combine([@entity_character], [character_id, "recent_kills"], nil)
  end

  @doc "Key for kill comparison data"
  @spec kill_comparison(String.t(), String.t()) :: String.t()
  def kill_comparison(type, params) do
    combine(["kill_comparison"], [type, params], nil)
  end

  @doc "Alias for tracked_systems_list/0"
  @spec tracked_systems() :: String.t()
  def tracked_systems, do: tracked_systems_list()

  @doc "Key for configuration entries"
  @spec config(String.t()) :: String.t()
  def config(name) when is_binary(name),
    do: combine([@prefix_config], [name], nil)

  @doc "Key for a specific zkill recent kill"
  @spec zkill_recent_kill(integer() | String.t()) :: String.t()
  def zkill_recent_kill(kill_id) do
    combine([@prefix_zkill, "recent_kills"], [kill_id], nil)
  end

  @doc "Key for system kills"
  @spec system_kills(integer() | String.t(), integer() | String.t()) :: String.t()
  def system_kills(system_id, limit) do
    combine([@prefix_esi, @entity_kills], [system_id, limit], nil)
  end

  @doc "Key for a killmail"
  @spec kill(integer() | String.t()) :: String.t()
  def kill(id), do: combine([@prefix_dedup, @entity_killmail], [id], nil)

  @doc "Key for inventory type search"
  @spec search_inventory_type(String.t(), boolean()) :: String.t()
  def search_inventory_type(query, strict) do
    combine([@prefix_esi, "search"], [query, strict], nil)
  end

  # ── Validation & Inspection ────────────────────────────────────────────────────
  # Delegate to KeyGenerator functions

  @doc "Returns true if the key contains at least one separator and two parts"
  @spec valid?(String.t()) :: boolean()
  def valid?(key), do: WandererNotifier.Infrastructure.Cache.KeyGenerator.valid_key?(key)

  @doc "Extracts wildcard segments from a key given a pattern"
  @spec extract_pattern(String.t(), String.t()) :: [String.t()]
  def extract_pattern(key, pattern),
    do: WandererNotifier.Infrastructure.Cache.KeyGenerator.extract_pattern(key, pattern)

  @doc """
  Returns structured info about a cache key or {:error, :invalid_key}.
  """
  @spec map_key_info(String.t()) :: map() | {:error, :invalid_key}
  def map_key_info(key), do: WandererNotifier.Infrastructure.Cache.KeyGenerator.parse_key(key)
end
