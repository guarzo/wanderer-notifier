defmodule WandererNotifier.Cache.Facade do
  @moduledoc """
  Unified cache facade providing domain-specific methods for cache operations.

  This facade provides a high-level interface for cache operations across the application,
  abstracting the underlying cache implementation and providing domain-specific methods
  for common cache operations.

  ## Features

  - Domain-specific cache methods for characters, corporations, alliances, systems
  - Versioned cache keys for deployment safety
  - Automatic TTL management based on data types
  - Comprehensive error handling and logging
  - Performance monitoring integration
  - Type specifications for all operations

  ## Usage

  ```elixir
  # Get character data
  {:ok, character} = WandererNotifier.Cache.Facade.get_character(123456)

  # Get system information
  {:ok, system} = WandererNotifier.Cache.Facade.get_system(30000142)

  # Store with custom TTL
  :ok = WandererNotifier.Cache.Facade.put_with_ttl("custom:key", value, 3600)
  ```
  """

  require Logger

  alias WandererNotifier.Cache.Adapter
  alias WandererNotifier.Cache.Config
  alias WandererNotifier.Cache.KeyGenerator
  alias WandererNotifier.Cache.Metrics

  @type cache_key :: String.t()
  @type cache_value :: term()
  @type cache_result :: {:ok, cache_value()} | {:error, term()}
  @type ttl_seconds :: non_neg_integer() | :infinity | nil

  # Version for cache key generation - increment when cache structure changes
  @cache_version "v1"

  @doc """
  Gets character data from cache.

  ## Parameters
  - character_id: EVE character ID
  - opts: Additional options (default: [])

  ## Returns
  - {:ok, character_data} if found
  - {:error, :not_found} if not found
  - {:error, reason} on error

  ## Examples
      iex> WandererNotifier.Cache.Facade.get_character(123456)
      {:ok, %{id: 123456, name: "Test Character", corporation_id: 98765}}

      iex> WandererNotifier.Cache.Facade.get_character(999999)
      {:error, :not_found}
  """
  @spec get_character(integer() | String.t(), keyword()) :: cache_result()
  def get_character(character_id, opts \\ []) do
    key = versioned_key("esi", "character", character_id)

    case get_from_cache(key, opts) do
      {:ok, result} ->
        log_cache_access(:character, character_id, :hit)
        {:ok, result}

      {:error, :not_found} = error ->
        log_cache_access(:character, character_id, :miss)
        error

      {:error, reason} = error ->
        log_cache_error(:character, character_id, reason)
        error
    end
  end

  @doc """
  Gets corporation data from cache.

  ## Parameters
  - corporation_id: EVE corporation ID
  - opts: Additional options (default: [])

  ## Returns
  - {:ok, corporation_data} if found
  - {:error, :not_found} if not found
  - {:error, reason} on error
  """
  @spec get_corporation(integer() | String.t(), keyword()) :: cache_result()
  def get_corporation(corporation_id, opts \\ []) do
    key = versioned_key("esi", "corporation", corporation_id)

    case get_from_cache(key, opts) do
      {:ok, result} ->
        log_cache_access(:corporation, corporation_id, :hit)
        {:ok, result}

      {:error, :not_found} = error ->
        log_cache_access(:corporation, corporation_id, :miss)
        error

      {:error, reason} = error ->
        log_cache_error(:corporation, corporation_id, reason)
        error
    end
  end

  @doc """
  Gets alliance data from cache.

  ## Parameters
  - alliance_id: EVE alliance ID
  - opts: Additional options (default: [])

  ## Returns
  - {:ok, alliance_data} if found
  - {:error, :not_found} if not found
  - {:error, reason} on error
  """
  @spec get_alliance(integer() | String.t(), keyword()) :: cache_result()
  def get_alliance(alliance_id, opts \\ []) do
    key = versioned_key("esi", "alliance", alliance_id)

    case get_from_cache(key, opts) do
      {:ok, result} ->
        log_cache_access(:alliance, alliance_id, :hit)
        {:ok, result}

      {:error, :not_found} = error ->
        log_cache_access(:alliance, alliance_id, :miss)
        error

      {:error, reason} = error ->
        log_cache_error(:alliance, alliance_id, reason)
        error
    end
  end

  @doc """
  Gets system data from cache.

  ## Parameters
  - system_id: EVE system ID
  - opts: Additional options (default: [])

  ## Returns
  - {:ok, system_data} if found
  - {:error, :not_found} if not found
  - {:error, reason} on error
  """
  @spec get_system(integer() | String.t(), keyword()) :: cache_result()
  def get_system(system_id, opts \\ []) do
    key = versioned_key("esi", "system", system_id)

    case get_from_cache(key, opts) do
      {:ok, result} ->
        log_cache_access(:system, system_id, :hit)
        {:ok, result}

      {:error, :not_found} = error ->
        log_cache_access(:system, system_id, :miss)
        error

      {:error, reason} = error ->
        log_cache_error(:system, system_id, reason)
        error
    end
  end

  @doc """
  Stores character data in cache with appropriate TTL.

  ## Parameters
  - character_id: EVE character ID
  - character_data: Character data to store
  - opts: Additional options (default: [])

  ## Returns
  - :ok on success
  - {:error, reason} on error
  """
  @spec put_character(integer() | String.t(), cache_value(), keyword()) :: :ok | {:error, term()}
  def put_character(character_id, character_data, opts \\ []) do
    key = versioned_key("esi", "character", character_id)
    ttl = get_domain_ttl(:character, opts)

    case put_in_cache(key, character_data, ttl) do
      :ok ->
        log_cache_operation(:character, character_id, :put)
        :ok

      {:error, reason} = error ->
        log_cache_error(:character, character_id, reason)
        error
    end
  end

  @doc """
  Stores corporation data in cache with appropriate TTL.

  ## Parameters
  - corporation_id: EVE corporation ID
  - corporation_data: Corporation data to store
  - opts: Additional options (default: [])

  ## Returns
  - :ok on success
  - {:error, reason} on error
  """
  @spec put_corporation(integer() | String.t(), cache_value(), keyword()) ::
          :ok | {:error, term()}
  def put_corporation(corporation_id, corporation_data, opts \\ []) do
    key = versioned_key("esi", "corporation", corporation_id)
    ttl = get_domain_ttl(:corporation, opts)

    case put_in_cache(key, corporation_data, ttl) do
      :ok ->
        log_cache_operation(:corporation, corporation_id, :put)
        :ok

      {:error, reason} = error ->
        log_cache_error(:corporation, corporation_id, reason)
        error
    end
  end

  @doc """
  Stores alliance data in cache with appropriate TTL.

  ## Parameters
  - alliance_id: EVE alliance ID
  - alliance_data: Alliance data to store
  - opts: Additional options (default: [])

  ## Returns
  - :ok on success
  - {:error, reason} on error
  """
  @spec put_alliance(integer() | String.t(), cache_value(), keyword()) :: :ok | {:error, term()}
  def put_alliance(alliance_id, alliance_data, opts \\ []) do
    key = versioned_key("esi", "alliance", alliance_id)
    ttl = get_domain_ttl(:alliance, opts)

    case put_in_cache(key, alliance_data, ttl) do
      :ok ->
        log_cache_operation(:alliance, alliance_id, :put)
        :ok

      {:error, reason} = error ->
        log_cache_error(:alliance, alliance_id, reason)
        error
    end
  end

  @doc """
  Stores system data in cache with appropriate TTL.

  ## Parameters
  - system_id: EVE system ID
  - system_data: System data to store
  - opts: Additional options (default: [])

  ## Returns
  - :ok on success
  - {:error, reason} on error
  """
  @spec put_system(integer() | String.t(), cache_value(), keyword()) :: :ok | {:error, term()}
  def put_system(system_id, system_data, opts \\ []) do
    key = versioned_key("esi", "system", system_id)
    ttl = get_domain_ttl(:system, opts)

    case put_in_cache(key, system_data, ttl) do
      :ok ->
        log_cache_operation(:system, system_id, :put)
        :ok

      {:error, reason} = error ->
        log_cache_error(:system, system_id, reason)
        error
    end
  end

  @doc """
  Stores a value in cache with custom TTL.

  ## Parameters
  - key: Cache key
  - value: Value to store
  - ttl: Time-to-live in seconds, :infinity, or nil for default

  ## Returns
  - :ok on success
  - {:error, reason} on error
  """
  @spec put_with_ttl(cache_key(), cache_value(), ttl_seconds()) :: :ok | {:error, term()}
  def put_with_ttl(key, value, ttl) do
    versioned_key = add_version_to_key(key)

    case put_in_cache(versioned_key, value, ttl) do
      :ok ->
        log_cache_operation(:custom, key, :put)
        :ok

      {:error, reason} = error ->
        log_cache_error(:custom, key, reason)
        error
    end
  end

  @doc """
  Gets a value from cache by key.

  ## Parameters
  - key: Cache key
  - opts: Additional options (default: [])

  ## Returns
  - {:ok, value} if found
  - {:error, :not_found} if not found
  - {:error, reason} on error
  """
  @spec get(cache_key(), keyword()) :: cache_result()
  def get(key, opts \\ []) do
    versioned_key = add_version_to_key(key)

    case get_from_cache(versioned_key, opts) do
      {:ok, result} ->
        log_cache_access(:custom, key, :hit)
        {:ok, result}

      {:error, :not_found} = error ->
        log_cache_access(:custom, key, :miss)
        error

      {:error, reason} = error ->
        log_cache_error(:custom, key, reason)
        error
    end
  end

  @doc """
  Deletes a value from cache by key.

  ## Parameters
  - key: Cache key

  ## Returns
  - :ok on success
  - {:error, reason} on error
  """
  @spec delete(cache_key()) :: :ok | {:error, term()}
  def delete(key) do
    versioned_key = add_version_to_key(key)

    case delete_from_cache(versioned_key) do
      {:ok, _} ->
        log_cache_operation(:custom, key, :delete)
        :ok

      :ok ->
        log_cache_operation(:custom, key, :delete)
        :ok

      {:error, reason} = error ->
        log_cache_error(:custom, key, reason)
        error
    end
  end

  @doc """
  Checks if a key exists in cache.

  ## Parameters
  - key: Cache key

  ## Returns
  - true if key exists
  - false if key doesn't exist
  """
  @spec exists?(cache_key()) :: boolean()
  def exists?(key) do
    versioned_key = add_version_to_key(key)

    case get_from_cache(versioned_key) do
      {:ok, _} -> true
      {:error, :not_found} -> false
      {:error, _} -> false
    end
  end

  @doc """
  Gets type/universe data from cache.

  ## Parameters
  - type_id: EVE type ID
  - opts: Additional options (default: [])

  ## Returns
  - {:ok, type_data} if found
  - {:error, :not_found} if not found
  - {:error, reason} on error
  """
  @spec get_type(integer() | String.t(), keyword()) :: cache_result()
  def get_type(type_id, opts \\ []) do
    key = versioned_key("esi", "type", type_id)

    case get_from_cache(key, opts) do
      {:ok, result} ->
        log_cache_access(:type, type_id, :hit)
        {:ok, result}

      {:error, :not_found} = error ->
        log_cache_access(:type, type_id, :miss)
        error

      {:error, reason} = error ->
        log_cache_error(:type, type_id, reason)
        error
    end
  end

  @doc """
  Stores type/universe data in cache with appropriate TTL.

  ## Parameters
  - type_id: EVE type ID
  - type_data: Type data to store
  - opts: Additional options (default: [])

  ## Returns
  - :ok on success
  - {:error, reason} on error
  """
  @spec put_type(integer() | String.t(), cache_value(), keyword()) :: :ok | {:error, term()}
  def put_type(type_id, type_data, opts \\ []) do
    key = versioned_key("esi", "type", type_id)
    ttl = get_domain_ttl(:type, opts)

    case put_in_cache(key, type_data, ttl) do
      :ok ->
        log_cache_operation(:type, type_id, :put)
        :ok

      {:error, reason} = error ->
        log_cache_error(:type, type_id, reason)
        error
    end
  end

  @doc """
  Gets killmail data from cache.

  ## Parameters
  - kill_id: Killmail ID
  - killmail_hash: Killmail hash
  - opts: Additional options (default: [])

  ## Returns
  - {:ok, killmail_data} if found
  - {:error, :not_found} if not found
  - {:error, reason} on error
  """
  @spec get_killmail(integer() | String.t(), String.t(), keyword()) :: cache_result()
  def get_killmail(kill_id, killmail_hash, opts \\ []) do
    key = versioned_key("esi", "killmail", "#{kill_id}:#{killmail_hash}")

    case get_from_cache(key, opts) do
      {:ok, result} ->
        log_cache_access(:killmail, kill_id, :hit)
        {:ok, result}

      {:error, :not_found} = error ->
        log_cache_access(:killmail, kill_id, :miss)
        error

      {:error, reason} = error ->
        log_cache_error(:killmail, kill_id, reason)
        error
    end
  end

  @doc """
  Stores killmail data in cache with appropriate TTL.

  ## Parameters
  - kill_id: Killmail ID
  - killmail_hash: Killmail hash
  - killmail_data: Killmail data to store
  - opts: Additional options (default: [])

  ## Returns
  - :ok on success
  - {:error, reason} on error
  """
  @spec put_killmail(integer() | String.t(), String.t(), cache_value(), keyword()) :: :ok | {:error, term()}
  def put_killmail(kill_id, killmail_hash, killmail_data, opts \\ []) do
    key = versioned_key("esi", "killmail", "#{kill_id}:#{killmail_hash}")
    ttl = get_domain_ttl(:killmail, opts)

    case put_in_cache(key, killmail_data, ttl) do
      :ok ->
        log_cache_operation(:killmail, kill_id, :put)
        :ok

      {:error, reason} = error ->
        log_cache_error(:killmail, kill_id, reason)
        error
    end
  end

  @doc """
  Gets custom data from cache with a specific key pattern.

  ## Parameters
  - key_pattern: String or list of key components
  - opts: Additional options (default: [])

  ## Returns
  - {:ok, data} if found
  - {:error, :not_found} if not found
  - {:error, reason} on error
  """
  @spec get_custom(String.t() | [String.t()], keyword()) :: cache_result()
  def get_custom(key_pattern, opts \\ []) do
    key = build_custom_key(key_pattern)

    case get_from_cache(key, opts) do
      {:ok, result} ->
        log_cache_access(:custom, key_pattern, :hit)
        {:ok, result}

      {:error, :not_found} = error ->
        log_cache_access(:custom, key_pattern, :miss)
        error

      {:error, reason} = error ->
        log_cache_error(:custom, key_pattern, reason)
        error
    end
  end

  @doc """
  Stores custom data in cache with a specific key pattern.

  ## Parameters
  - key_pattern: String or list of key components
  - data: Data to store
  - opts: Additional options (default: [])

  ## Returns
  - :ok on success
  - {:error, reason} on error
  """
  @spec put_custom(String.t() | [String.t()], cache_value(), keyword()) :: :ok | {:error, term()}
  def put_custom(key_pattern, data, opts \\ []) do
    key = build_custom_key(key_pattern)
    ttl = Keyword.get(opts, :ttl, Config.ttl_for(:default))

    case put_in_cache(key, data, ttl) do
      :ok ->
        log_cache_operation(:custom, key_pattern, :put)
        :ok

      {:error, reason} = error ->
        log_cache_error(:custom, key_pattern, reason)
        error
    end
  end

  @doc """
  Deletes custom data from cache with a specific key pattern.

  ## Parameters
  - key_pattern: String or list of key components

  ## Returns
  - :ok on success
  - {:error, reason} on error
  """
  @spec delete_custom(String.t() | [String.t()]) :: :ok | {:error, term()}
  def delete_custom(key_pattern) do
    key = build_custom_key(key_pattern)

    case delete_from_cache(key) do
      {:ok, _} ->
        log_cache_operation(:custom, key_pattern, :delete)
        :ok

      :ok ->
        log_cache_operation(:custom, key_pattern, :delete)
        :ok

      {:error, reason} = error ->
        log_cache_error(:custom, key_pattern, reason)
        error
    end
  end

  @doc """
  Clears all cache entries.

  ## Returns
  - :ok on success
  - {:error, reason} on error
  """
  @spec clear() :: :ok | {:error, term()}
  def clear do
    cache_name = Config.cache_name()
    start_time = System.monotonic_time(:millisecond)

    result =
      case Adapter.clear(cache_name) do
        {:ok, _} ->
          Logger.info("Cache cleared successfully")
          :ok

        :ok ->
          Logger.info("Cache cleared successfully")
          :ok

        {:error, reason} = error ->
          Logger.error("Failed to clear cache: #{inspect(reason)}")
          error
      end

    duration = System.monotonic_time(:millisecond) - start_time
    Metrics.record_operation_time(:clear, duration)

    result
  end

  @doc """
  Gets cache statistics and information.

  ## Returns
  - Map with cache statistics
  """
  @spec stats() :: map()
  def stats do
    cache_name = Config.cache_name()

    case Adapter.adapter() do
      Cachex ->
        {:ok, stats} = Cachex.stats(cache_name)
        stats

      _other ->
        %{adapter: Adapter.adapter(), version: @cache_version}
    end
  end

  # Private functions

  defp versioned_key(prefix, entity_type, id) do
    KeyGenerator.combine([prefix, entity_type], [id], @cache_version)
  end

  defp add_version_to_key(key) do
    "#{key}:#{@cache_version}"
  end

  defp get_from_cache(key, _opts \\ []) do
    cache_name = Config.cache_name()
    start_time = System.monotonic_time(:millisecond)

    result =
      case Adapter.get(cache_name, key) do
        {:ok, nil} -> {:error, :not_found}
        {:ok, value} -> {:ok, value}
        {:error, reason} -> {:error, reason}
      end

    duration = System.monotonic_time(:millisecond) - start_time
    Metrics.record_operation_time(:get, duration)

    result
  end

  defp put_in_cache(key, value, ttl) do
    cache_name = Config.cache_name()
    start_time = System.monotonic_time(:millisecond)

    result =
      case Adapter.set(cache_name, key, value, ttl) do
        {:ok, _} -> :ok
        :ok -> :ok
        {:error, reason} -> {:error, reason}
      end

    duration = System.monotonic_time(:millisecond) - start_time
    Metrics.record_operation_time(:put, duration)

    result
  end

  defp delete_from_cache(key) do
    cache_name = Config.cache_name()
    start_time = System.monotonic_time(:millisecond)

    result = Adapter.del(cache_name, key)

    duration = System.monotonic_time(:millisecond) - start_time
    Metrics.record_operation_time(:delete, duration)

    result
  end

  defp build_custom_key(key_pattern) when is_binary(key_pattern) do
    add_version_to_key(key_pattern)
  end

  defp build_custom_key(key_pattern) when is_list(key_pattern) do
    key = Enum.join(key_pattern, ":")
    add_version_to_key(key)
  end

  defp get_domain_ttl(domain, opts) do
    case Keyword.get(opts, :ttl) do
      nil ->
        case domain do
          :character -> Config.ttl_for(:character)
          :corporation -> Config.ttl_for(:corporation)
          :alliance -> Config.ttl_for(:alliance)
          :system -> Config.ttl_for(:system)
          :type -> Config.ttl_for(:type)
          :killmail -> Config.ttl_for(:killmail)
          :default -> Config.ttl_for(:default)
        end

      ttl ->
        ttl
    end
  end

  defp log_cache_access(domain, id, result, duration \\ 0) do
    Logger.debug("Cache #{result} for #{domain}:#{id}")

    case result do
      :hit -> Metrics.record_hit(domain, id)
      :miss -> Metrics.record_miss(domain, id)
    end

    # Record operation for analytics
    try do
      key = versioned_key("esi", Atom.to_string(domain), id)

      WandererNotifier.Cache.Analytics.record_operation(
        :get,
        key,
        result,
        duration,
        %{data_type: domain, id: id}
      )
    rescue
      # Don't fail cache operations if analytics fails
      _ -> :ok
    end
  end

  defp log_cache_operation(domain, id, operation) do
    Logger.debug("Cache #{operation} for #{domain}:#{id}")
  end

  defp log_cache_error(domain, id, reason) do
    Logger.warning("Cache error for #{domain}:#{id}: #{inspect(reason)}")
  end
end
