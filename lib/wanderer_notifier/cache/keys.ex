defmodule WandererNotifier.Cache.Keys do
  @moduledoc """
  Module for generating and validating cache keys.
  Provides functions for creating standardized cache keys for various data types.

  Key Format: `prefix:entity_type:id` or `prefix:name`
  Examples:
    - `map:system:12345`
    - `tracked:character:98765`
    - `recent:kills`
  """

  import WandererNotifier.Cache.KeyGenerator

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

  # Separator
  @separator ":"

  @doc false
  defp join_parts(parts) when is_list(parts) do
    Enum.join(parts, @separator)
  end

  @doc false
  defp combine(fixed_parts, dynamic_parts, extra) do
    fixed_parts
    |> Enum.map(&to_string/1)
    |> Kernel.++(Enum.map(dynamic_parts, &to_string/1))
    |> Kernel.++(if(extra, do: [to_string(extra)], else: []))
    |> join_parts()
  end

  # Generate standard cache key functions
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

  # Special case functions that don't fit the standard pattern
  @doc "Key for a killmail with hash"
  @spec killmail(integer() | String.t(), integer() | String.t(), String.t() | nil) :: String.t()
  def killmail(kill_id, killmail_hash, extra \\ nil),
    do: combine([@prefix_esi, @entity_killmail], [kill_id, killmail_hash], extra)

  @doc "Key for zkill recent kills"
  @spec zkill_recent_kills(String.t() | nil) :: String.t()
  def zkill_recent_kills(extra \\ nil),
    do: combine([@prefix_zkill, "recent_kills"], [], extra)

  @doc "Key for map systems list"
  @spec map_systems(String.t() | nil) :: String.t()
  def map_systems(extra \\ nil),
    do: combine([@prefix_map, "systems"], [], extra)

  @doc "Key for map system IDs"
  @spec map_system_ids(String.t() | nil) :: String.t()
  def map_system_ids(extra \\ nil),
    do: combine([@prefix_map, "system_ids"], [], extra)

  @doc "Key for critical startup data"
  @spec critical_startup_data(String.t() | nil) :: String.t()
  def critical_startup_data(extra \\ nil),
    do: combine([@prefix_critical, "startup_data"], [], extra)

  @doc "Key for systems array"
  @spec systems_array(String.t() | nil) :: String.t()
  def systems_array(extra \\ nil),
    do: combine([@prefix_array, "systems"], [], extra)

  @doc "Key for killmails array"
  @spec killmails_array(String.t() | nil) :: String.t()
  def killmails_array(extra \\ nil),
    do: combine([@prefix_array, "killmails"], [], extra)

  @doc "Key for recent killmails list"
  @spec recent_killmails_list(String.t() | nil) :: String.t()
  def recent_killmails_list(extra \\ nil),
    do: combine([@prefix_recent, @entity_kills], [], extra)

  @doc "Key for application state"
  @spec application_state(String.t() | nil) :: String.t()
  def application_state(extra \\ nil),
    do: combine([@prefix_state, "application"], [], extra)

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
    [@prefix_exists, @entity_killmail, killmail_id, character_id, role]
    |> Enum.map(&to_string/1)
    |> join_parts()
  end

  @doc "Key for a character's recent kills"
  @spec character_recent_kills(integer() | String.t()) :: String.t()
  def character_recent_kills(character_id) do
    combine([@entity_character], [character_id, "recent_kills"], nil)
  end

  @doc "Key for the full character list"
  @spec character_list() :: String.t()
  def character_list do
    combine([@prefix_map], ["characters"], nil)
  end

  @doc "Key for kill comparison data"
  @spec kill_comparison(String.t(), String.t()) :: String.t()
  def kill_comparison(type, params) do
    combine(["kill_comparison"], [type, params], nil)
  end

  @doc "Alias for tracked_systems_list/0"
  @spec tracked_systems() :: String.t()
  def tracked_systems, do: tracked_systems_list()

  @doc "Key for tracked systems list"
  @spec tracked_systems_list() :: String.t()
  def tracked_systems_list, do: combine([@prefix_tracked], ["systems"], nil)

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

  # ── Validation & Inspection ────────────────────────────────────────────────────

  @doc "Returns true if the key contains at least one separator and two parts"
  @spec valid?(String.t()) :: boolean()
  def valid?(key) when is_binary(key) do
    String.contains?(key, @separator) and length(String.split(key, @separator)) >= 2
  end

  def valid?(_), do: false

  @doc "Extracts wildcard segments from a key given a pattern"
  @spec extract_pattern(String.t(), String.t()) :: [String.t()]
  def extract_pattern(key, pattern) when is_binary(key) and is_binary(pattern) do
    key_parts = String.split(key, @separator)
    pattern_parts = String.split(pattern, @separator)

    if length(key_parts) == length(pattern_parts) do
      do_extract(key_parts, pattern_parts, [])
    else
      []
    end
  end

  def extract_pattern(_, _), do: []

  defp do_extract([], [], acc), do: Enum.reverse(acc)
  defp do_extract([k | kr], ["*" | pr], acc), do: do_extract(kr, pr, [k | acc])
  defp do_extract([k | kr], [p | pr], acc) when k == p, do: do_extract(kr, pr, acc)
  defp do_extract(_, _, _), do: []

  @doc """
  Returns structured info about a cache key or {:error, :invalid_key}.
  """
  @spec map_key_info(String.t()) :: map() | {:error, :invalid_key}
  def map_key_info(key) when is_binary(key) do
    if valid?(key) do
      parts = String.split(key, @separator)

      case parts do
        [prefix, entity, id | rest] ->
          %{prefix: prefix, entity_type: entity, id: id, parts: parts, extra: rest}

        [prefix, name] ->
          %{prefix: prefix, name: name, parts: parts}

        _ ->
          %{parts: parts}
      end
    else
      {:error, :invalid_key}
    end
  end

  def map_key_info(_), do: {:error, :invalid_key}

  @doc "Key for the full system list"
  @spec system_list() :: String.t()
  def system_list, do: combine([@prefix_map], ["systems"], nil)

  @doc "Key for a killmail"
  @spec kill(integer() | String.t()) :: String.t()
  def kill(id), do: combine([@prefix_dedup, @entity_killmail], [id], nil)
end
