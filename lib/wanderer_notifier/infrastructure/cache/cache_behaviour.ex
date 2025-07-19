defmodule WandererNotifier.Infrastructure.Cache.CacheBehaviour do
  @moduledoc """
  Unified behaviour for cache implementations.
  This consolidates functionality from both repository and cache operations.

  ## Implementation Guidelines

  1. Cache implementations should handle:
     - Basic CRUD operations (get/set/delete)
     - TTL support
     - Atomic updates
     - Batch operations
     - Error handling
     - Versioned keys for deployment safety
     - Performance monitoring integration

  2. Error handling:
     - All operations should return {:ok, value} or {:error, reason}
     - Not found should be {:error, :not_found}
     - Implementation errors should provide meaningful error reasons

  3. Performance considerations:
     - Implementations should be optimized for high-volume operations
     - Consider using batch operations where possible
     - Handle concurrent access appropriately
     - Cache is populated on-demand for optimal startup performance

  4. Versioning and deployment:
     - Support versioned cache keys for safe deployments
     - Handle cache invalidation across versions
     - Provide migration support for key format changes
  """

  @type key :: term()
  @type value :: term()
  @type reason :: term()
  @type opts :: keyword()

  @doc """
  Gets a value from the cache by key.

  ## Parameters
  - key: The cache key
  - opts: Options for the get operation (optional)

  ## Returns
  - {:ok, value} if found
  - {:error, :not_found} if not found
  - {:error, reason} on error
  """
  @callback get(key :: key(), opts :: opts()) :: {:ok, value()} | {:error, :not_found | reason()}

  @doc """
  Sets a value in the cache with an optional TTL.

  ## Parameters
  - key: The cache key
  - value: The value to cache
  - ttl: Time-to-live in seconds (nil for no TTL)

  ## Returns
  - :ok on success
  - {:ok, value()} on success (implementation dependent)
  - {:error, reason} on failure
  """
  @callback set(key :: key(), value :: value(), ttl :: non_neg_integer() | nil) ::
              :ok | {:ok, value()} | {:error, reason()}

  @doc """
  Puts a value in the cache without TTL.

  ## Parameters
  - key: The cache key
  - value: The value to cache

  ## Returns
  - :ok on success
  - {:ok, value()} on success (implementation dependent)
  - {:error, reason} on failure
  """
  @callback put(key :: key(), value :: value()) :: :ok | {:ok, value()} | {:error, reason()}

  @doc """
  Deletes a value from the cache by key.

  ## Parameters
  - key: The cache key

  ## Returns
  - :ok on success
  - {:ok, value()} on success (implementation dependent)
  - {:error, reason} on failure
  """
  @callback delete(key :: key()) :: :ok | {:ok, value()} | {:error, reason()}

  @doc """
  Clears the entire cache.

  ## Returns
  - :ok on success
  - {:ok, value()} on success (implementation dependent)
  - {:error, reason} on failure
  """
  @callback clear() :: :ok | {:ok, value()} | {:error, reason()}

  @doc """
  Gets and updates a value atomically using the provided update function.
  The update function receives the current value (or nil) and should return {current_value, new_value}.

  ## Parameters
  - key: The cache key
  - update_fun: Function to transform the current value

  ## Returns
  - {:ok, {current_value, new_value}} on success
  - {:ok, current_value} on success (simplified return)
  - {:error, reason} on failure
  """
  @callback get_and_update(key :: key(), update_fun :: (value() -> {value(), value()})) ::
              {:ok, {value(), value()}} | {:ok, value()} | {:error, reason()}

  @doc """
  Gets multiple values from the cache by keys.
  Returns a list of {:ok, value} or {:error, reason} for each key.

  ## Parameters
  - keys: List of cache keys

  ## Returns
  - {:ok, list({:ok, value()} | {:error, reason()})} on success
  - {:error, reason} on failure
  """
  @callback mget(keys :: list(key())) ::
              {:ok, list({:ok, value()} | {:error, reason()})} | {:error, reason()}

  @doc """
  Gets a killmail from the cache by ID.

  ## Parameters
  - kill_id: The killmail ID (string or integer)

  ## Returns
  - {:ok, killmail} if found
  - {:error, :not_found} if not found
  - {:error, :not_cached} if not cached
  - {:error, reason} on error
  """
  @callback get_kill(kill_id :: String.t() | integer()) ::
              {:ok, map()} | {:error, :not_found | :not_cached | reason()}

  @doc """
  Gets recent kills from cache.
  This is a specialized function for retrieving recent killmail data.
  """
  @callback get_recent_kills() :: list()

  @doc """
  Initializes batch logging for cache operations.
  Used for performance optimization in batch processing scenarios.
  """
  @callback init_batch_logging() :: :ok

  @doc """
  Checks if a key exists in the cache.

  ## Parameters
  - key: The cache key

  ## Returns
  - true if key exists
  - false if key doesn't exist
  """
  @callback exists?(key :: key()) :: boolean()

  @doc """
  Gets cache statistics and performance metrics.

  ## Returns
  - {:ok, map()} with cache statistics
  - {:error, reason} on failure
  """
  @callback stats() :: {:ok, map()} | {:error, reason()}

  @doc """
  Gets domain-specific character data from cache.

  ## Parameters
  - character_id: EVE character ID
  - opts: Additional options

  ## Returns
  - {:ok, character_data} if found
  - {:error, :not_found} if not found
  - {:error, reason} on error
  """
  @callback get_character(character_id :: integer() | String.t(), opts :: opts()) ::
              {:ok, map()} | {:error, :not_found | reason()}

  @doc """
  Gets domain-specific corporation data from cache.

  ## Parameters
  - corporation_id: EVE corporation ID  
  - opts: Additional options

  ## Returns
  - {:ok, corporation_data} if found
  - {:error, :not_found} if not found
  - {:error, reason} on error
  """
  @callback get_corporation(corporation_id :: integer() | String.t(), opts :: opts()) ::
              {:ok, map()} | {:error, :not_found | reason()}

  @doc """
  Gets domain-specific alliance data from cache.

  ## Parameters
  - alliance_id: EVE alliance ID
  - opts: Additional options

  ## Returns
  - {:ok, alliance_data} if found
  - {:error, :not_found} if not found
  - {:error, reason} on error
  """
  @callback get_alliance(alliance_id :: integer() | String.t(), opts :: opts()) ::
              {:ok, map()} | {:error, :not_found | reason()}

  @doc """
  Gets domain-specific system data from cache.

  ## Parameters
  - system_id: EVE system ID
  - opts: Additional options

  ## Returns
  - {:ok, system_data} if found
  - {:error, :not_found} if not found
  - {:error, reason} on error
  """
  @callback get_system(system_id :: integer() | String.t(), opts :: opts()) ::
              {:ok, map()} | {:error, :not_found | reason()}

  @doc """
  Stores value in cache with custom TTL.

  ## Parameters
  - key: Cache key
  - value: Value to store
  - ttl: Time-to-live in seconds, :infinity, or nil for default

  ## Returns
  - :ok on success
  - {:error, reason} on error
  """
  @callback put_with_ttl(
              key :: key(),
              value :: value(),
              ttl :: non_neg_integer() | :infinity | nil
            ) ::
              :ok | {:error, reason()}

  @optional_callbacks [
    get_recent_kills: 0,
    init_batch_logging: 0,
    clear: 0,
    mget: 1,
    get_kill: 1,
    exists?: 1,
    stats: 0,
    get_character: 2,
    get_corporation: 2,
    get_alliance: 2,
    get_system: 2,
    put_with_ttl: 3
  ]
end
