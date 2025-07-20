defmodule WandererNotifier.Infrastructure.Cache do
  @moduledoc """
  Simplified cache module using Cachex directly.

  This replaces the complex Facade → Adapter → Cachex architecture with direct Cachex access.
  No behaviors, no abstractions - just simple cache operations with domain-specific helpers.

  ## Usage Examples

      # Core operations
      Cache.get("my:key")
      Cache.put("my:key", value, ttl: :timer.hours(1))
      Cache.delete("my:key")
      
      # Domain helpers  
      Cache.get_character(character_id)
      Cache.put_character(character_id, character_data)
      
      # Custom TTL
      Cache.put_with_ttl("custom:key", value, :timer.minutes(30))
  """

  require Logger

  # Cache configuration
  @default_cache_name :wanderer_notifier_cache
  @default_ttl :timer.hours(24)

  # TTL configurations
  @character_ttl :timer.hours(24)
  @corporation_ttl :timer.hours(24)
  @alliance_ttl :timer.hours(24)
  @system_ttl :timer.hours(1)
  @universe_type_ttl :timer.hours(24)
  @killmail_ttl :timer.minutes(30)
  @map_data_ttl :timer.hours(1)

  @type cache_key :: String.t()
  @type cache_value :: term()
  @type cache_result :: {:ok, cache_value()} | {:error, :not_found}
  @type ttl_value :: pos_integer() | :infinity | nil

  # ============================================================================
  # Configuration Functions
  # ============================================================================

  def cache_name, do: Application.get_env(:wanderer_notifier, :cache_name, @default_cache_name)
  def default_cache_name, do: @default_cache_name

  def character_ttl, do: @character_ttl
  def corporation_ttl, do: @corporation_ttl
  def alliance_ttl, do: @alliance_ttl
  def system_ttl, do: @system_ttl
  def universe_type_ttl, do: @universe_type_ttl
  def killmail_ttl, do: @killmail_ttl
  def map_ttl, do: @map_data_ttl

  def ttl_for(:map_data), do: @map_data_ttl
  def ttl_for(_), do: @default_ttl

  # ============================================================================
  # Key Generation Functions
  # ============================================================================

  defmodule Keys do
    @moduledoc false

    def character(id), do: "esi:character:#{id}"
    def corporation(id), do: "esi:corporation:#{id}"
    def alliance(id), do: "esi:alliance:#{id}"
    def system(id), do: "esi:system:#{id}"
    def universe_type(id), do: "esi:universe_type:#{id}"
    def killmail(id), do: "killmail:#{id}"
    def notification_dedup(key), do: "notification:dedup:#{key}"
    def map_systems, do: "map:systems"
    def map_characters, do: "map:characters"
    def custom(prefix, suffix), do: "#{prefix}:#{suffix}"
  end

  # ============================================================================
  # Core Cache Operations
  # ============================================================================

  @doc """
  Gets a value from the cache by key.

  ## Examples
      iex> Cache.get("user:123")
      {:ok, %{name: "John"}}
      
      iex> Cache.get("nonexistent")
      {:error, :not_found}
  """
  @spec get(cache_key()) :: cache_result()
  def get(key) when is_binary(key) do
    case Cachex.get(cache_name(), key) do
      {:ok, nil} -> {:error, :not_found}
      {:ok, value} -> {:ok, value}
      {:error, _reason} = error -> error
    end
  end

  @doc """
  Puts a value in the cache with optional TTL.

  ## Examples
      iex> Cache.put("user:123", %{name: "John"})
      :ok
      
      iex> Cache.put("session:abc", token, :timer.hours(1))
      :ok
  """
  @spec put(cache_key(), cache_value(), ttl_value()) :: :ok | {:error, term()}
  def put(key, value, ttl \\ nil) when is_binary(key) do
    cache_name = cache_name()

    case ttl do
      nil ->
        Cachex.put(cache_name, key, value)

      ttl_value when is_integer(ttl_value) or ttl_value == :infinity ->
        Cachex.put(cache_name, key, value, ttl: ttl_value)
    end
  end

  @doc """
  Deletes a value from the cache.

  ## Examples
      iex> Cache.delete("user:123")
      :ok
  """
  @spec delete(cache_key()) :: :ok
  def delete(key) when is_binary(key) do
    Cachex.del(cache_name(), key)
    :ok
  end

  @doc """
  Checks if a key exists in the cache.

  ## Examples
      iex> Cache.exists?("user:123")
      true
  """
  @spec exists?(cache_key()) :: boolean()
  def exists?(key) when is_binary(key) do
    case Cachex.exists?(cache_name(), key) do
      {:ok, exists} -> exists
      {:error, _} -> false
    end
  end

  @doc """
  Clears all entries from the cache.

  ## Examples
      iex> Cache.clear()
      :ok
  """
  @spec clear() :: :ok
  def clear do
    Cachex.clear(cache_name())
    :ok
  end

  # ============================================================================
  # Domain-Specific Helpers (Essential Only)
  # ============================================================================

  @doc """
  Gets character data from cache.
  """
  @spec get_character(integer()) :: cache_result()
  def get_character(character_id) when is_integer(character_id) do
    get(Keys.character(character_id))
  end

  @doc """
  Puts character data in cache with 24-hour TTL.
  """
  @spec put_character(integer(), map()) :: :ok | {:error, term()}
  def put_character(character_id, data) when is_integer(character_id) and is_map(data) do
    put(Keys.character(character_id), data, character_ttl())
  end

  @doc """
  Gets corporation data from cache.
  """
  @spec get_corporation(integer()) :: cache_result()
  def get_corporation(corporation_id) when is_integer(corporation_id) do
    get(Keys.corporation(corporation_id))
  end

  @doc """
  Puts corporation data in cache with 24-hour TTL.
  """
  @spec put_corporation(integer(), map()) :: :ok | {:error, term()}
  def put_corporation(corporation_id, data) when is_integer(corporation_id) and is_map(data) do
    put(Keys.corporation(corporation_id), data, corporation_ttl())
  end

  @doc """
  Gets alliance data from cache.
  """
  @spec get_alliance(integer()) :: cache_result()
  def get_alliance(alliance_id) when is_integer(alliance_id) do
    get(Keys.alliance(alliance_id))
  end

  @doc """
  Puts alliance data in cache with 24-hour TTL.
  """
  @spec put_alliance(integer(), map()) :: :ok | {:error, term()}
  def put_alliance(alliance_id, data) when is_integer(alliance_id) and is_map(data) do
    put(Keys.alliance(alliance_id), data, alliance_ttl())
  end

  @doc """
  Gets system data from cache.
  """
  @spec get_system(integer()) :: cache_result()
  def get_system(system_id) when is_integer(system_id) do
    get(Keys.system(system_id))
  end

  @doc """
  Puts system data in cache with 1-hour TTL.
  """
  @spec put_system(integer(), map()) :: :ok | {:error, term()}
  def put_system(system_id, data) when is_integer(system_id) and is_map(data) do
    put(Keys.system(system_id), data, system_ttl())
  end

  @doc """
  Gets universe type data from cache.
  """
  @spec get_universe_type(integer()) :: cache_result()
  def get_universe_type(type_id) when is_integer(type_id) do
    get(Keys.universe_type(type_id))
  end

  @doc """
  Puts universe type data in cache with 24-hour TTL.
  """
  @spec put_universe_type(integer(), map()) :: :ok | {:error, term()}
  def put_universe_type(type_id, data) when is_integer(type_id) and is_map(data) do
    put(Keys.universe_type(type_id), data, universe_type_ttl())
  end

  # ============================================================================
  # Additional Domain Helpers for ESI Compatibility
  # ============================================================================

  @doc """
  Gets character data from cache (ESI compatible with opts parameter).
  """
  @spec get_character(integer(), keyword()) :: cache_result()
  def get_character(character_id, _opts) when is_integer(character_id) do
    get_character(character_id)
  end

  @doc """
  Puts character data in cache (ESI compatible with opts parameter).
  """
  @spec put_character(integer(), map(), keyword()) :: :ok | {:error, term()}
  def put_character(character_id, data, _opts) when is_integer(character_id) and is_map(data) do
    put_character(character_id, data)
  end

  @doc """
  Gets corporation data from cache (ESI compatible with opts parameter).
  """
  @spec get_corporation(integer(), keyword()) :: cache_result()
  def get_corporation(corporation_id, _opts) when is_integer(corporation_id) do
    get_corporation(corporation_id)
  end

  @doc """
  Puts corporation data in cache (ESI compatible with opts parameter).
  """
  @spec put_corporation(integer(), map(), keyword()) :: :ok | {:error, term()}
  def put_corporation(corporation_id, data, _opts)
      when is_integer(corporation_id) and is_map(data) do
    put_corporation(corporation_id, data)
  end

  @doc """
  Gets alliance data from cache (ESI compatible with opts parameter).
  """
  @spec get_alliance(integer(), keyword()) :: cache_result()
  def get_alliance(alliance_id, _opts) when is_integer(alliance_id) do
    get_alliance(alliance_id)
  end

  @doc """
  Puts alliance data in cache (ESI compatible with opts parameter).
  """
  @spec put_alliance(integer(), map(), keyword()) :: :ok | {:error, term()}
  def put_alliance(alliance_id, data, _opts) when is_integer(alliance_id) and is_map(data) do
    put_alliance(alliance_id, data)
  end

  @doc """
  Gets system data from cache (ESI compatible with opts parameter).
  """
  @spec get_system(integer(), keyword()) :: cache_result()
  def get_system(system_id, _opts) when is_integer(system_id) do
    get_system(system_id)
  end

  @doc """
  Puts system data in cache (ESI compatible with opts parameter).
  """
  @spec put_system(integer(), map(), keyword()) :: :ok | {:error, term()}
  def put_system(system_id, data, _opts) when is_integer(system_id) and is_map(data) do
    put_system(system_id, data)
  end

  @doc """
  Gets type data from cache.
  """
  @spec get_type(integer(), keyword()) :: cache_result()
  def get_type(type_id, _opts) when is_integer(type_id) do
    get_universe_type(type_id)
  end

  @doc """
  Puts type data in cache.
  """
  @spec put_type(integer(), map(), keyword()) :: :ok | {:error, term()}
  def put_type(type_id, data, _opts) when is_integer(type_id) and is_map(data) do
    put_universe_type(type_id, data)
  end

  @doc """
  Gets killmail data from cache.
  """
  @spec get_killmail(integer(), String.t(), keyword()) :: cache_result()
  def get_killmail(kill_id, _killmail_hash, _opts) when is_integer(kill_id) do
    get(Keys.killmail(kill_id))
  end

  @doc """
  Puts killmail data in cache.
  """
  @spec put_killmail(integer(), String.t(), map(), keyword()) :: :ok | {:error, term()}
  def put_killmail(kill_id, _killmail_hash, data, _opts)
      when is_integer(kill_id) and is_map(data) do
    put(Keys.killmail(kill_id), data, killmail_ttl())
  end

  # ============================================================================
  # Convenience Functions
  # ============================================================================

  @doc """
  Puts a value in cache with explicit TTL (alias for put/3 for backward compatibility).

  ## Examples
      iex> Cache.put_with_ttl("custom:key", value, :timer.minutes(30))
      :ok
  """
  @spec put_with_ttl(cache_key(), cache_value(), ttl_value()) :: :ok | {:error, term()}
  def put_with_ttl(key, value, ttl) do
    put(key, value, ttl)
  end

  @doc """
  Gets cache statistics.

  ## Examples
      iex> Cache.stats()
      %{size: 150, hit_rate: 0.85}
  """
  @spec stats() :: map()
  def stats do
    cache_name = cache_name()

    case Cachex.stats(cache_name) do
      {:ok, stats} ->
        Map.take(stats, [:size, :hit_rate, :miss_rate, :eviction_count])

      {:error, _} ->
        %{size: 0, hit_rate: 0.0, miss_rate: 0.0, eviction_count: 0}
    end
  end

  @doc """
  Gets cache size (number of entries).

  ## Examples
      iex> Cache.size()
      150
  """
  @spec size() :: non_neg_integer()
  def size do
    case Cachex.size(cache_name()) do
      {:ok, size} -> size
      {:error, _} -> 0
    end
  end
end
