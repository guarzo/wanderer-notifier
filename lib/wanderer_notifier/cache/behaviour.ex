defmodule WandererNotifier.Cache.Behaviour do
  @moduledoc """
  Defines the behaviour for cache implementations.
  This is a unified behavior that combines functionality from both repository and cache operations.

  ## Implementation Guidelines

  1. Cache implementations should handle:
     - Basic CRUD operations (get/set/delete)
     - TTL support
     - Atomic updates
     - Batch operations
     - Error handling

  2. Error handling:
     - All operations should return {:ok, value} or {:error, reason}
     - Not found should be {:error, :not_found}
     - Implementation errors should provide meaningful error reasons

  3. Performance considerations:
     - Implementations should be optimized for high-volume operations
     - Consider using batch operations where possible
     - Handle concurrent access appropriately
  """

  @type key :: term()
  @type value :: term()
  @type reason :: term()

  @doc """
  Gets a value from the cache by key.
  Returns {:ok, value} if found, {:error, :not_found} if not found, or {:error, reason} on error.
  """
  @callback get(key :: key()) :: {:ok, value()} | {:error, :not_found | reason()}

  @doc """
  Sets a value in the cache with an optional TTL in seconds.
  """
  @callback set(key :: key(), value :: value(), ttl :: non_neg_integer() | nil) ::
              :ok | {:ok, value()} | {:error, reason()}

  @doc """
  Puts a value in the cache without TTL.
  """
  @callback put(key :: key(), value :: value()) :: {:ok, value()} | {:error, reason()}

  @doc """
  Deletes a value from the cache by key.
  """
  @callback delete(key :: key()) :: {:ok, value()} | {:error, reason()}

  @doc """
  Clears the entire cache.
  """
  @callback clear() :: {:ok, value()} | {:error, reason()}

  @doc """
  Gets and updates a value atomically using the provided update function.
  The update function receives the current value (or nil) and should return {current_value, new_value}.
  Returns {:ok, {current_value, new_value}} on success or {:error, reason} on failure.
  """
  @callback get_and_update(key :: key(), update_fun :: (value() -> {value(), value()})) ::
              {:ok, {value(), value()}} | {:error, reason()}

  @doc """
  Gets recent kills from cache.
  This is a specialized function that was part of the repository behavior.
  """
  @callback get_recent_kills() :: list()

  @doc """
  Initializes batch logging for cache operations.
  """
  @callback init_batch_logging() :: :ok

  @doc """
  Gets multiple values from the cache by keys.
  Returns a list of {:ok, value} or {:error, reason} for each key.
  """
  @callback mget(keys :: list(key())) ::
              {:ok, list({:ok, value()} | {:error, reason()})} | {:error, reason()}

  @doc """
  Gets a killmail from the cache by ID.
  Returns {:ok, killmail} if found, {:error, :not_found} if not found, or {:error, reason} on error.
  """
  @callback get_kill(kill_id :: String.t() | integer()) ::
              {:ok, map()} | {:error, :not_found | :not_cached | reason()}

  @optional_callbacks [
    get_recent_kills: 0,
    init_batch_logging: 0
  ]
end
