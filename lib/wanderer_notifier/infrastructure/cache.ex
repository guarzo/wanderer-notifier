defmodule WandererNotifier.Infrastructure.Cache do
  @moduledoc """
  Simplified cache module using Cachex directly.

  This replaces the complex Facade -> Adapter -> Cachex architecture with direct Cachex access.
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

  ## Key Generation

  Use `Cache.Keys` module for consistent key generation:

      Cache.Keys.character(12345)      # => "esi:character:12345"
      Cache.Keys.map_systems()         # => "map:systems"

  ## TTL Configuration

  TTL values are managed via `Cache.TtlConfig`:

      Cache.ttl(:character)            # => 86400000 (24 hours)
      Cache.ttl(:system)               # => 3600000 (1 hour)
  """

  require Logger

  alias WandererNotifier.Infrastructure.Cache.Keys
  alias WandererNotifier.Infrastructure.Cache.TtlConfig

  # Cache configuration
  @default_cache_name :wanderer_notifier_cache

  @type cache_key :: String.t()
  @type cache_value :: term()
  @type cache_result :: {:ok, cache_value()} | {:error, :not_found}
  @type ttl_value :: pos_integer() | :infinity | nil

  # ============================================================================
  # Configuration Functions
  # ============================================================================

  def cache_name, do: Application.get_env(:wanderer_notifier, :cache_name, @default_cache_name)

  def cache_stats_enabled?,
    do: Application.get_env(:wanderer_notifier, :cache_stats_enabled, true)

  def default_cache_name, do: @default_cache_name

  defdelegate ttl(type), to: TtlConfig

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
    start_time = System.monotonic_time()

    result =
      case Cachex.get(cache_name(), key) do
        {:ok, nil} -> {:error, :not_found}
        {:ok, value} -> {:ok, value}
        {:error, _reason} = error -> error
      end

    # Emit telemetry for cache operations
    :telemetry.execute(
      [:wanderer_notifier, :cache, :get],
      %{duration: System.monotonic_time() - start_time},
      %{key: key, result: elem(result, 0)}
    )

    result
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
    start_time = System.monotonic_time()
    cache_name = cache_name()

    result = put_value_with_ttl(cache_name, key, value, ttl)
    final_result = handle_put_result(result)

    emit_put_telemetry(start_time, key, final_result)
    final_result
  end

  defp put_value_with_ttl(cache_name, key, value, ttl) do
    case ttl do
      nil ->
        Cachex.put(cache_name, key, value)

      ttl_value when is_integer(ttl_value) or ttl_value == :infinity ->
        Cachex.put(cache_name, key, value, ttl: ttl_value)
    end
  end

  defp handle_put_result(result) do
    case result do
      {:ok, true} -> :ok
      {:ok, false} -> {:error, :not_stored}
      error -> error
    end
  end

  defp emit_put_telemetry(start_time, key, final_result) do
    result_type =
      case final_result do
        :ok -> :ok
        {:error, _} -> :error
      end

    :telemetry.execute(
      [:wanderer_notifier, :cache, :put],
      %{duration: System.monotonic_time() - start_time},
      %{key: key, result: result_type}
    )
  end

  @doc """
  Deletes a value from the cache.

  ## Examples
      iex> Cache.delete("user:123")
      {:ok, :deleted}
  """
  @spec delete(cache_key()) :: {:ok, :deleted} | {:error, term()}
  def delete(key) when is_binary(key) do
    case Cachex.del(cache_name(), key) do
      {:ok, _} -> {:ok, :deleted}
      {:error, reason} -> {:error, reason}
    end
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
      {:ok, :cleared}
  """
  @spec clear() :: {:ok, :cleared} | {:error, term()}
  def clear do
    case Cachex.clear(cache_name()) do
      {:ok, _} -> {:ok, :cleared}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Atomically updates a windowed counter for rate limiting.
  If the current window is still valid, increments the counter.
  If the window has expired, resets to 1 with a new window start time.

  ## Examples
      iex> Cache.update_windowed_counter("webhook:123", 2000)
      {:ok, %{requests: 1, window_start: 1640995200000}}

      iex> Cache.update_windowed_counter("webhook:123", 2000)
      {:ok, %{requests: 2, window_start: 1640995200000}}
  """
  @spec update_windowed_counter(cache_key(), pos_integer(), ttl_value()) ::
          {:ok, map()} | {:error, term()}
  def update_windowed_counter(key, window_ms, ttl \\ nil)
      when is_binary(key) and is_integer(window_ms) do
    cache_name = cache_name()
    current_time = System.system_time(:millisecond)

    # Use Cachex.transaction for atomic read-modify-write operation
    case Cachex.transaction(cache_name, [key], fn ->
           handle_windowed_counter_transaction(cache_name, key, window_ms, current_time, ttl)
         end) do
      {:ok, result} ->
        result

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp handle_windowed_counter_transaction(cache_name, key, window_ms, current_time, ttl) do
    case Cachex.get(cache_name, key) do
      {:ok, nil} ->
        create_new_window_counter(cache_name, key, current_time, ttl)

      {:ok, %{requests: requests, window_start: window_start}} ->
        update_existing_window_counter(
          cache_name,
          key,
          requests,
          window_start,
          window_ms,
          current_time,
          ttl
        )

      {:error, reason} ->
        {:error, reason}

      _ ->
        # Fallback case - corrupted data, reset
        create_new_window_counter(cache_name, key, current_time, ttl)
    end
  end

  defp create_new_window_counter(cache_name, key, current_time, ttl) do
    new_value = %{requests: 1, window_start: current_time}
    put_windowed_counter_value(cache_name, key, new_value, ttl)
  end

  defp update_existing_window_counter(
         cache_name,
         key,
         requests,
         window_start,
         window_ms,
         current_time,
         ttl
       ) do
    if window_still_valid?(window_start, current_time, window_ms) do
      increment_window_counter(cache_name, key, requests, window_start, ttl)
    else
      create_new_window_counter(cache_name, key, current_time, ttl)
    end
  end

  defp window_still_valid?(window_start, current_time, window_ms) do
    current_time - window_start < window_ms
  end

  defp increment_window_counter(cache_name, key, requests, window_start, ttl) do
    updated_value = %{requests: requests + 1, window_start: window_start}
    put_windowed_counter_value(cache_name, key, updated_value, ttl)
  end

  defp put_windowed_counter_value(cache_name, key, value, ttl) do
    case Cachex.put(cache_name, key, value, ttl: ttl) do
      {:ok, true} -> {:ok, value}
      error -> error
    end
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
    put(Keys.character(character_id), data, ttl(:character))
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
    put(Keys.corporation(corporation_id), data, ttl(:corporation))
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
    put(Keys.alliance(alliance_id), data, ttl(:alliance))
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
    put(Keys.system(system_id), data, ttl(:system))
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
    put(Keys.universe_type(type_id), data, ttl(:universe_type))
  end

  @doc """
  Gets item price data from cache.
  """
  @spec get_item_price(integer()) :: cache_result()
  def get_item_price(type_id) when is_integer(type_id) do
    get(Keys.item_price(type_id))
  end

  @doc """
  Puts item price data in cache with 6-hour TTL.
  """
  @spec put_item_price(integer(), map()) :: :ok | {:error, term()}
  def put_item_price(type_id, data) when is_integer(type_id) and is_map(data) do
    put(Keys.item_price(type_id), data, ttl(:item_price))
  end

  # ============================================================================
  # Additional Domain-Specific Helpers
  # ============================================================================

  @doc """
  Gets system name from cache.
  """
  @spec get_system_name(integer()) :: cache_result()
  def get_system_name(system_id) when is_integer(system_id) do
    get(Keys.system_name(system_id))
  end

  @doc """
  Puts system name in cache with 1-hour TTL.
  """
  @spec put_system_name(integer(), String.t()) :: :ok | {:error, term()}
  def put_system_name(system_id, name) when is_integer(system_id) and is_binary(name) do
    put(Keys.system_name(system_id), name, ttl(:system))
  end

  @doc """
  Gets corporation data with shorter key for performance.
  """
  @spec get_corporation_data(integer()) :: cache_result()
  def get_corporation_data(corporation_id) when is_integer(corporation_id) do
    get(Keys.corporation_data(corporation_id))
  end

  @doc """
  Puts corporation data with shorter key and 24-hour TTL.
  """
  @spec put_corporation_data(integer(), map()) :: :ok | {:error, term()}
  def put_corporation_data(corporation_id, data)
      when is_integer(corporation_id) and is_map(data) do
    put(Keys.corporation_data(corporation_id), data, ttl(:corporation))
  end

  @doc """
  Gets ship type data from cache.
  """
  @spec get_ship_type(integer()) :: cache_result()
  def get_ship_type(type_id) when is_integer(type_id) do
    get(Keys.ship_type(type_id))
  end

  @doc """
  Puts ship type data in cache with 24-hour TTL.
  """
  @spec put_ship_type(integer(), map()) :: :ok | {:error, term()}
  def put_ship_type(type_id, data) when is_integer(type_id) and is_map(data) do
    put(Keys.ship_type(type_id), data, ttl(:universe_type))
  end

  # ============================================================================
  # Tracking Domain Helpers
  # ============================================================================

  @doc """
  Gets tracked character data from cache.
  """
  @spec get_tracked_character(integer()) :: cache_result()
  def get_tracked_character(character_id) when is_integer(character_id) do
    get(Keys.tracked_character(character_id))
  end

  @doc """
  Puts tracked character data in cache with 1-hour TTL.
  """
  @spec put_tracked_character(integer(), map()) :: :ok | {:error, term()}
  def put_tracked_character(character_id, character_data)
      when is_integer(character_id) and is_map(character_data) do
    put(Keys.tracked_character(character_id), character_data, ttl(:system))
  end

  @doc """
  Checks if a character is tracked.
  """
  @spec is_character_tracked?(integer()) :: boolean()
  def is_character_tracked?(character_id) when is_integer(character_id) do
    exists?(Keys.tracked_character(character_id))
  end

  @doc """
  Gets tracked system data from cache.
  """
  @spec get_tracked_system(String.t()) :: cache_result()
  def get_tracked_system(system_id) when is_binary(system_id) do
    get(Keys.tracked_system(system_id))
  end

  @doc """
  Puts tracked system data in cache with 1-hour TTL.
  """
  @spec put_tracked_system(String.t(), map()) :: :ok | {:error, term()}
  def put_tracked_system(system_id, system_data)
      when is_binary(system_id) and is_map(system_data) do
    put(Keys.tracked_system(system_id), system_data, ttl(:system))
  end

  @doc """
  Checks if a system is tracked.
  """
  @spec is_system_tracked?(String.t()) :: boolean()
  def is_system_tracked?(system_id) when is_binary(system_id) do
    exists?(Keys.tracked_system(system_id))
  end

  @doc """
  Puts the list of tracked systems with 1-hour TTL.
  """
  @spec put_tracked_systems_list(list()) :: :ok | {:error, term()}
  def put_tracked_systems_list(systems) when is_list(systems) do
    put(Keys.tracked_systems_list(), systems, ttl(:system))
  end

  @doc """
  Puts the list of tracked characters with 1-hour TTL.
  """
  @spec put_tracked_characters_list(list()) :: :ok | {:error, term()}
  def put_tracked_characters_list(characters) when is_list(characters) do
    put(Keys.tracked_characters_list(), characters, ttl(:system))
  end

  # ============================================================================
  # Convenience Functions
  # ============================================================================

  @doc """
  Puts a value in cache with explicit TTL (alias for put/3).

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
