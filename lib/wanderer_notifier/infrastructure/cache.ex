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
  @item_price_ttl :timer.hours(6)
  @license_ttl :timer.minutes(20)

  @type cache_key :: String.t()
  @type cache_value :: term()
  @type cache_result :: {:ok, cache_value()} | {:error, :not_found}
  @type ttl_value :: pos_integer() | :infinity | nil

  # ============================================================================
  # Configuration Functions
  # ============================================================================

  def cache_name, do: Application.get_env(:wanderer_notifier, :cache_name, @default_cache_name)
  def default_cache_name, do: @default_cache_name

  # Simplified TTL access - single function with pattern matching
  def ttl(:character), do: @character_ttl
  def ttl(:corporation), do: @corporation_ttl
  def ttl(:alliance), do: @alliance_ttl
  def ttl(:system), do: @system_ttl
  def ttl(:universe_type), do: @universe_type_ttl
  def ttl(:killmail), do: @killmail_ttl
  def ttl(:map_data), do: @map_data_ttl
  def ttl(:item_price), do: @item_price_ttl
  def ttl(:license), do: @license_ttl
  def ttl(:health_check), do: :timer.seconds(1)
  def ttl(_), do: @default_ttl

  # ============================================================================
  # Key Generation Functions
  # ============================================================================

  defmodule Keys do
    @moduledoc """
    Centralized cache key generation for consistent naming patterns.

    All cache keys should be generated through these functions to ensure
    consistency and avoid duplication across the codebase.
    """

    # ESI-related keys (external API data)
    def character(id), do: "esi:character:#{id}"
    def corporation(id), do: "esi:corporation:#{id}"
    def alliance(id), do: "esi:alliance:#{id}"
    def system(id), do: "esi:system:#{id}"
    def system_name(id), do: "esi:system_name:#{id}"
    def universe_type(id), do: "esi:universe_type:#{id}"
    def item_price(id), do: "esi:item_price:#{id}"

    # Killmail-related keys
    def killmail(id), do: "killmail:#{id}"
    def websocket_dedup(killmail_id), do: "websocket_dedup:#{killmail_id}"

    # Notification keys
    def notification_dedup(key), do: "notification:dedup:#{key}"

    # Map-related keys
    def map_systems, do: "map:systems"
    def map_characters, do: "map:characters"

    # Tracking keys for individual lookups (O(1) performance)
    def tracked_character(id), do: "tracking:character:#{id}"
    def tracked_system(id), do: "tracking:system:#{id}"
    def tracked_systems_list, do: "tracking:systems_list"
    def tracked_characters_list, do: "tracking:characters_list"

    # Map state keys
    def map_state(map_slug), do: "map:state:#{map_slug}"
    def map_subscription_data, do: "map:subscription_data"

    # Domain-specific data keys (using shorter prefixes for better performance)
    def corporation_data(id), do: "corporation:#{id}"
    def ship_type(id), do: "ship_type:#{id}"
    def solar_system(id), do: "solar_system:#{id}"

    # Scheduler keys
    def scheduler_primed(scheduler_name), do: "scheduler:primed:#{scheduler_name}"
    def scheduler_data(scheduler_name), do: "scheduler:data:#{scheduler_name}"

    # Status and reporting keys
    def status_report(minute), do: "status_report:#{minute}"

    # Janice appraisal keys
    def janice_appraisal(hash), do: "janice:appraisal:#{hash}"

    # License validation keys
    def license_validation, do: "license_validation_result"

    # Generic helper for custom keys
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

    result =
      case ttl do
        nil ->
          Cachex.put(cache_name, key, value)

        ttl_value when is_integer(ttl_value) or ttl_value == :infinity ->
          Cachex.put(cache_name, key, value, ttl: ttl_value)
      end

    case result do
      {:ok, true} -> :ok
      {:ok, false} -> {:error, :not_stored}
      error -> error
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
  Gets the list of all tracked systems.
  """
  @spec get_tracked_systems_list() :: cache_result()
  def get_tracked_systems_list do
    get(Keys.tracked_systems_list())
  end

  @doc """
  Puts the list of tracked systems with 1-hour TTL.
  """
  @spec put_tracked_systems_list(list()) :: :ok | {:error, term()}
  def put_tracked_systems_list(systems) when is_list(systems) do
    put(Keys.tracked_systems_list(), systems, ttl(:system))
  end

  @doc """
  Gets the list of all tracked characters.
  """
  @spec get_tracked_characters_list() :: cache_result()
  def get_tracked_characters_list do
    get(Keys.tracked_characters_list())
  end

  @doc """
  Puts the list of tracked characters with 1-hour TTL.
  """
  @spec put_tracked_characters_list(list()) :: :ok | {:error, term()}
  def put_tracked_characters_list(characters) when is_list(characters) do
    put(Keys.tracked_characters_list(), characters, ttl(:system))
  end

  # ============================================================================
  # Batch Operations
  # ============================================================================

  @doc """
  Gets multiple values from the cache in a single operation.

  ## Examples
      iex> Cache.get_batch(["user:1", "user:2", "user:3"])
      %{
        "user:1" => {:ok, %{name: "John"}},
        "user:2" => {:ok, %{name: "Jane"}},
        "user:3" => {:error, :not_found}
      }
  """
  @spec get_batch([cache_key()]) :: %{cache_key() => cache_result()}
  def get_batch(keys) when is_list(keys) do
    cache_name = cache_name()

    # Get all keys individually since Cachex doesn't have get_many
    # This is still more efficient than multiple separate calls from client code
    results =
      Enum.map(keys, fn key ->
        case Cachex.get(cache_name, key) do
          {:ok, nil} -> {key, {:error, :not_found}}
          {:ok, value} -> {key, {:ok, value}}
          {:error, reason} -> {key, {:error, reason}}
        end
      end)

    # Convert to map
    Enum.into(results, %{})
  end

  @doc """
  Puts multiple values in the cache in a single operation.

  ## Examples
      iex> Cache.put_batch([{"user:1", %{name: "John"}}, {"user:2", %{name: "Jane"}}])
      :ok
  """
  @spec put_batch([{cache_key(), cache_value()}]) :: :ok | {:error, term()}
  def put_batch(entries) when is_list(entries) do
    put_batch_with_ttl(Enum.map(entries, fn {key, value} -> {key, value, nil} end))
  end

  @doc """
  Puts multiple values in the cache with individual TTLs.

  ## Examples
      iex> Cache.put_batch_with_ttl([
      ...>   {"session:1", %{user: "John"}, :timer.hours(1)},
      ...>   {"session:2", %{user: "Jane"}, :timer.hours(2)}
      ...> ])
      :ok
  """
  @spec put_batch_with_ttl([{cache_key(), cache_value(), ttl_value()}]) :: :ok | {:error, term()}
  def put_batch_with_ttl(entries) when is_list(entries) do
    cache_name = cache_name()

    # Process each entry
    results =
      Enum.map(entries, fn
        {key, value, nil} ->
          Cachex.put(cache_name, key, value)

        {key, value, ttl} when is_integer(ttl) or ttl == :infinity ->
          Cachex.put(cache_name, key, value, ttl: ttl)
      end)

    # Check if all operations succeeded
    case Enum.find(results, &match?({:error, _}, &1)) do
      nil ->
        :ok

      error ->
        Logger.error("Batch put failed", error: inspect(error))
        error
    end
  end

  # ============================================================================
  # Domain-Specific Batch Helpers
  # ============================================================================

  @doc """
  Gets multiple characters from cache in a single operation.

  ## Examples
      iex> Cache.get_characters_batch([123, 456, 789])
      %{
        123 => {:ok, %{name: "Character One"}},
        456 => {:ok, %{name: "Character Two"}},
        789 => {:error, :not_found}
      }
  """
  @spec get_characters_batch([integer()]) :: %{integer() => cache_result()}
  def get_characters_batch(character_ids) when is_list(character_ids) do
    keys = Enum.map(character_ids, &Keys.character/1)
    results = get_batch(keys)

    # Map back to character IDs
    Enum.into(character_ids, %{}, fn id ->
      key = Keys.character(id)
      {id, Map.get(results, key, {:error, :not_found})}
    end)
  end

  @doc """
  Puts multiple characters in cache with 24-hour TTL.

  ## Examples
      iex> Cache.put_characters_batch([{123, %{name: "Char1"}}, {456, %{name: "Char2"}}])
      :ok
  """
  @spec put_characters_batch([{integer(), map()}]) :: :ok | {:error, term()}
  def put_characters_batch(character_entries) when is_list(character_entries) do
    entries =
      Enum.map(character_entries, fn {id, data} ->
        {Keys.character(id), data, ttl(:character)}
      end)

    put_batch_with_ttl(entries)
  end

  @doc """
  Gets multiple systems from cache in a single operation.
  """
  @spec get_systems_batch([integer()]) :: %{integer() => cache_result()}
  def get_systems_batch(system_ids) when is_list(system_ids) do
    keys = Enum.map(system_ids, &Keys.system/1)
    results = get_batch(keys)

    # Map back to system IDs
    Enum.into(system_ids, %{}, fn id ->
      key = Keys.system(id)
      {id, Map.get(results, key, {:error, :not_found})}
    end)
  end

  @doc """
  Puts multiple systems in cache with 1-hour TTL.
  """
  @spec put_systems_batch([{integer(), map()}]) :: :ok | {:error, term()}
  def put_systems_batch(system_entries) when is_list(system_entries) do
    entries =
      Enum.map(system_entries, fn {id, data} ->
        {Keys.system(id), data, ttl(:system)}
      end)

    put_batch_with_ttl(entries)
  end

  @doc """
  Gets multiple universe types from cache in a single operation.
  """
  @spec get_universe_types_batch([integer()]) :: %{integer() => cache_result()}
  def get_universe_types_batch(type_ids) when is_list(type_ids) do
    keys = Enum.map(type_ids, &Keys.universe_type/1)
    results = get_batch(keys)

    # Map back to type IDs
    Enum.into(type_ids, %{}, fn id ->
      key = Keys.universe_type(id)
      {id, Map.get(results, key, {:error, :not_found})}
    end)
  end

  @doc """
  Puts multiple universe types in cache with 24-hour TTL.
  """
  @spec put_universe_types_batch([{integer(), map()}]) :: :ok | {:error, term()}
  def put_universe_types_batch(type_entries) when is_list(type_entries) do
    entries =
      Enum.map(type_entries, fn {id, data} ->
        {Keys.universe_type(id), data, ttl(:universe_type)}
      end)

    put_batch_with_ttl(entries)
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

  # ============================================================================
  # Namespace Management
  # ============================================================================

  @doc """
  Clears all cache entries with keys matching the given namespace prefix.

  ## Examples
      iex> Cache.clear_namespace("esi")
      {:ok, 42}  # Cleared 42 entries

      iex> Cache.clear_namespace("tracking")
      {:ok, 0}   # No entries found
  """
  @spec clear_namespace(String.t()) :: {:ok, integer()} | {:error, term()}
  def clear_namespace(namespace) when is_binary(namespace) do
    cache_name = cache_name()

    try do
      # Get all keys matching the namespace
      matching_keys = get_keys_by_namespace(namespace)

      # Delete all matching keys
      Enum.each(matching_keys, fn key ->
        Cachex.del(cache_name, key)
      end)

      {:ok, length(matching_keys)}
    rescue
      error ->
        Logger.error("Failed to clear namespace",
          namespace: namespace,
          error: inspect(error)
        )

        {:error, error}
    end
  end

  @doc """
  Gets statistics for a specific namespace.

  ## Examples
      iex> Cache.get_namespace_stats("esi")
      %{
        count: 150,
        size_bytes: 524288,
        oldest_entry: ~U[2024-01-01 12:00:00Z],
        newest_entry: ~U[2024-01-02 15:30:00Z]
      }
  """
  @spec get_namespace_stats(String.t()) :: map()
  def get_namespace_stats(namespace) when is_binary(namespace) do
    matching_keys = get_keys_by_namespace(namespace)

    %{
      count: length(matching_keys),
      namespace: namespace,
      sample_keys: Enum.take(matching_keys, 5)
    }
  end

  @doc """
  Lists all namespaces in the cache.

  ## Examples
      iex> Cache.list_namespaces()
      ["esi", "tracking", "notification", "scheduler", "websocket_dedup", "dedup"]
  """
  @spec list_namespaces() :: [String.t()]
  def list_namespaces do
    cache_name = cache_name()

    # Get all keys and extract namespaces
    case Cachex.keys(cache_name) do
      {:ok, keys} ->
        keys
        |> Enum.map(&extract_namespace/1)
        |> Enum.reject(&is_nil/1)
        |> Enum.uniq()
        |> Enum.sort()

      {:error, _} ->
        []
    end
  end

  # ============================================================================
  # Private Namespace Functions
  # ============================================================================

  defp get_keys_by_namespace(namespace) do
    cache_name = cache_name()
    prefix = "#{namespace}:"

    case Cachex.keys(cache_name) do
      {:ok, keys} ->
        Enum.filter(keys, &String.starts_with?(&1, prefix))

      {:error, _} ->
        []
    end
  end

  defp extract_namespace(key) when is_binary(key) do
    case String.split(key, ":", parts: 2) do
      [namespace, _rest] -> namespace
      _ -> nil
    end
  end

  defp extract_namespace(_), do: nil
end
