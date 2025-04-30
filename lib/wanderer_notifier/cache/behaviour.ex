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

  @doc """
  Gets a value from the cache by key.
  Returns {:ok, value} if found, {:error, :not_found} if not found, or {:error, reason} on error.
  """
  @callback get(key :: any()) :: {:ok, any()} | {:error, :not_found | any()}

  @doc """
  Sets a value in the cache with an optional TTL in seconds.
  """
  @callback set(key :: any(), value :: any(), ttl :: non_neg_integer() | nil) ::
              :ok | {:ok, any()} | {:error, any()}

  @doc """
  Puts a value in the cache without TTL.
  """
  @callback put(key :: any(), value :: any()) :: :ok | {:ok, any()} | {:error, any()}

  @doc """
  Deletes a value from the cache by key.
  """
  @callback delete(key :: any()) :: :ok | {:ok, any()} | {:error, any()}

  @doc """
  Clears the entire cache.
  """
  @callback clear() :: :ok | {:ok, any()} | {:error, any()}

  @doc """
  Gets and updates a value atomically using the provided update function.
  The update function receives the current value (or nil) and should return {current_value, new_value}.
  """
  @callback get_and_update(key :: any(), update_fun :: (any() -> {any(), any()})) ::
              {:ok, any()} | {:error, any()}

  @doc """
  Gets recent kills from cache.
  This is a specialized function that was part of the repository behavior.
  """
  @callback get_recent_kills() :: list()

  @doc """
  Initializes batch logging for cache operations.
  """
  @callback init_batch_logging() :: :ok

  @optional_callbacks [
    get_recent_kills: 0,
    init_batch_logging: 0
  ]
end
