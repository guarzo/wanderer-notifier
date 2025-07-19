defmodule WandererNotifier.Infrastructure.Cache.CacheKey do
  @moduledoc """
  Struct for representing cache keys with type safety.
  Ensures consistent key formatting and provides pattern matching capabilities.
  """

  @type key_type ::
          :system
          | :character
          | :killmail
          | :corporation
          | :alliance
          | :ship_type
          | :type
          | :tracked_system
          | :tracked_character
          | :dedup_system
          | :dedup_character
          | :dedup_kill
          | :recent_kills
          | :config
          | :data
          | :custom

  @type t :: %__MODULE__{
          type: key_type(),
          prefix: String.t(),
          entity: String.t() | nil,
          id: String.t() | integer() | nil,
          extra: String.t() | nil,
          raw: String.t()
        }

  @enforce_keys [:type, :prefix, :raw]
  defstruct [:type, :prefix, :entity, :id, :extra, :raw]

  alias WandererNotifier.Infrastructure.Cache.Keys

  # Key type to function mapping
  @key_functions %{
    system: &Keys.system/1,
    character: &Keys.character/1,
    tracked_system: &Keys.tracked_system/1,
    tracked_character: &Keys.tracked_character/1,
    killmail: &Keys.kill/1,
    corporation: &Keys.corporation/1,
    alliance: &Keys.alliance/1,
    ship_type: &Keys.ship_type/1,
    type: &Keys.type/1,
    dedup_system: &Keys.dedup_system/1,
    dedup_character: &Keys.dedup_character/1,
    dedup_kill: &Keys.dedup_kill/1
  }

  @doc """
  Creates a new CacheKey struct.

  ## Examples

      iex> CacheKey.new(:system, 30000142)
      %CacheKey{type: :system, prefix: "map", entity: "system", id: 30000142, raw: "map:system:30000142"}

      iex> CacheKey.new(:character, "2118083819")
      %CacheKey{type: :character, prefix: "esi", entity: "character", id: "2118083819", raw: "esi:character:2118083819"}
  """
  @spec new(key_type(), String.t() | integer()) :: t()
  def new(type, id)
      when type in [
             :system,
             :character,
             :tracked_system,
             :tracked_character,
             :killmail,
             :corporation,
             :alliance,
             :ship_type,
             :type,
             :dedup_system,
             :dedup_character,
             :dedup_kill
           ] do
    key_func = Map.fetch!(@key_functions, type)
    raw_key = key_func.(id)
    parse_from_raw(type, raw_key)
  end

  @doc """
  Creates a CacheKey for a killmail with hash.

  ## Example

      iex> CacheKey.killmail(123456, "abc123hash")
      %CacheKey{type: :killmail, prefix: "esi", entity: "killmail", id: 123456, extra: "abc123hash", raw: "esi:killmail:123456:abc123hash"}
  """
  @spec killmail(integer() | String.t(), String.t()) :: t()
  def killmail(kill_id, killmail_hash) do
    raw_key = Keys.killmail(kill_id, killmail_hash)

    %__MODULE__{
      type: :killmail,
      prefix: "esi",
      entity: "killmail",
      id: kill_id,
      extra: killmail_hash,
      raw: raw_key
    }
  end

  @doc """
  Creates a CacheKey for recent kills.

  ## Example

      iex> CacheKey.recent_kills()
      %CacheKey{type: :recent_kills, prefix: "recent", entity: "kills", raw: "recent:kills"}
  """
  @spec recent_kills() :: t()
  def recent_kills() do
    raw_key = Keys.recent_killmails_list()

    %__MODULE__{
      type: :recent_kills,
      prefix: "recent",
      entity: "kills",
      raw: raw_key
    }
  end

  @doc """
  Creates a CacheKey for configuration entries.

  ## Example

      iex> CacheKey.config("feature_flags")
      %CacheKey{type: :config, prefix: "config", id: "feature_flags", raw: "config:feature_flags"}
  """
  @spec config(String.t()) :: t()
  def config(name) do
    raw_key = Keys.config(name)

    %__MODULE__{
      type: :config,
      prefix: "config",
      id: name,
      raw: raw_key
    }
  end

  @doc """
  Creates a CacheKey for arbitrary data.

  ## Example

      iex> CacheKey.data("user_settings", "theme")
      %CacheKey{type: :data, prefix: "data", id: "user_settings", extra: "theme", raw: "data:user_settings:theme"}
  """
  @spec data(String.t(), String.t() | nil) :: t()
  def data(key, extra \\ nil) do
    raw_key = Keys.data(key, extra)

    %__MODULE__{
      type: :data,
      prefix: "data",
      id: key,
      extra: extra,
      raw: raw_key
    }
  end

  @doc """
  Creates a CacheKey from a raw string key.
  Returns {:ok, cache_key} or {:error, :invalid_key}.

  ## Example

      iex> CacheKey.from_raw("map:system:30000142")
      {:ok, %CacheKey{type: :custom, prefix: "map", entity: "system", id: "30000142", raw: "map:system:30000142"}}
  """
  @spec from_raw(String.t()) :: {:ok, t()} | {:error, :invalid_key}
  def from_raw(raw_key) when is_binary(raw_key) do
    case Keys.map_key_info(raw_key) do
      {:error, :invalid_key} ->
        {:error, :invalid_key}

      key_info ->
        cache_key = %__MODULE__{
          type: determine_type(key_info),
          prefix: key_info.prefix,
          entity: Map.get(key_info, :entity),
          id: Map.get(key_info, :id),
          extra: Map.get(key_info, :extra),
          raw: raw_key
        }

        {:ok, cache_key}
    end
  end

  @doc """
  Returns the raw string representation of the cache key.

  ## Example

      iex> key = CacheKey.new(:system, 30000142)
      iex> CacheKey.to_string(key)
      "map:system:30000142"
  """
  @spec to_string(t()) :: String.t()
  def to_string(%__MODULE__{raw: raw}), do: raw

  @doc """
  Checks if a CacheKey is valid.

  ## Example

      iex> key = CacheKey.new(:system, 30000142)
      iex> CacheKey.valid?(key)
      true
  """
  @spec valid?(t()) :: boolean()
  def valid?(%__MODULE__{raw: raw}), do: Keys.valid?(raw)

  # Private functions

  defp parse_from_raw(type, raw_key) do
    case Keys.map_key_info(raw_key) do
      {:error, :invalid_key} ->
        raise ArgumentError, "Invalid key generated: #{raw_key}"

      key_info ->
        %__MODULE__{
          type: type,
          prefix: key_info.prefix,
          entity: Map.get(key_info, :entity),
          id: Map.get(key_info, :id),
          extra: Map.get(key_info, :extra),
          raw: raw_key
        }
    end
  end

  # Type mapping for cache keys
  @type_mappings %{
    {"map", "system"} => :system,
    {"esi", "character"} => :character,
    {"tracked", "system"} => :tracked_system,
    {"tracked", "character"} => :tracked_character,
    {"esi", "killmail"} => :killmail,
    {"esi", "corporation"} => :corporation,
    {"esi", "alliance"} => :alliance,
    {"dedup", "system"} => :dedup_system,
    {"dedup", "character"} => :dedup_character,
    {"dedup", "killmail"} => :dedup_kill,
    {"recent", "kills"} => :recent_kills
  }

  defp determine_type(key_info) do
    prefix = key_info.prefix
    entity = Map.get(key_info, :entity)

    cond do
      type = Map.get(@type_mappings, {prefix, entity}) -> type
      prefix == "config" -> :config
      prefix == "data" -> :data
      true -> :custom
    end
  end
end

defimpl String.Chars, for: WandererNotifier.Infrastructure.Cache.CacheKey do
  def to_string(cache_key), do: cache_key.raw
end
