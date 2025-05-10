defmodule WandererNotifier.Cache.CacheBehaviour do
  @moduledoc """
  Behaviour for cache operations.
  Defines the contract for modules that handle caching.
  """

  @doc """
  Gets a value from the cache.

  ## Parameters
  - key: The cache key
  - opts: Options for the get operation

  ## Returns
  - {:ok, value} on success
  - {:error, reason} on failure
  """
  @callback get(key :: any(), opts :: keyword()) :: {:ok, any()} | {:error, any()}

  @doc """
  Sets a value in the cache with a TTL.

  ## Parameters
  - key: The cache key
  - value: The value to cache
  - ttl: Time-to-live in milliseconds

  ## Returns
  - :ok on success
  - {:error, reason} on failure
  """
  @callback set(key :: any(), value :: any(), ttl :: integer()) :: :ok | {:error, any()}

  @doc """
  Puts a value in the cache with no TTL.

  ## Parameters
  - key: The cache key
  - value: The value to cache

  ## Returns
  - :ok on success
  - {:error, reason} on failure
  """
  @callback put(key :: any(), value :: any()) :: :ok | {:error, any()}

  @doc """
  Deletes a value from the cache.

  ## Parameters
  - key: The cache key

  ## Returns
  - :ok on success
  - {:error, reason} on failure
  """
  @callback delete(key :: any()) :: :ok | {:error, any()}

  @doc """
  Gets a value from the cache and updates it in one operation.

  ## Parameters
  - key: The cache key
  - update_fun: Function to transform the current value

  ## Returns
  - {:ok, current_value} on success
  - {:error, reason} on failure
  """
  @callback get_and_update(key :: any(), update_fun :: function()) ::
              {:ok, any()} | {:error, any()}
end
