defmodule WandererNotifier.Cache.Adapter do
  @moduledoc """
  Provides a unified interface for different cache adapters.

  This module abstracts the underlying cache implementation,
  allowing the application to switch between Cachex (production)
  and ETSCache (testing) transparently.
  """

  @doc """
  Gets the configured cache adapter.
  """
  def adapter do
    Application.get_env(:wanderer_notifier, :cache_adapter, Cachex)
  end

  @doc """
  Gets a value from the cache.
  """
  def get(cache_name, key) do
    case adapter() do
      Cachex ->
        Cachex.get(cache_name, key)

      WandererNotifier.Cache.ETSCache ->
        WandererNotifier.Cache.ETSCache.get(key, table: cache_name)

      WandererNotifier.Cache.SimpleETSCache ->
        WandererNotifier.Cache.SimpleETSCache.get(key)

      other ->
        {:error, {:unknown_adapter, other}}
    end
  end

  @doc """
  Sets a value in the cache with a TTL.
  """
  def set(cache_name, key, value, ttl \\ nil) do
    # Use default TTL if not specified
    ttl = 
      ttl || 
      (:default |> WandererNotifier.Cache.Config.ttl_for() |> :timer.seconds())

    case adapter() do
      Cachex ->
        Cachex.put(cache_name, key, value, ttl: ttl)

      WandererNotifier.Cache.ETSCache ->
        WandererNotifier.Cache.ETSCache.set(key, value, div(ttl, 1000), table: cache_name)

      WandererNotifier.Cache.SimpleETSCache ->
        WandererNotifier.Cache.SimpleETSCache.set(key, value, div(ttl, 1000))

      other ->
        {:error, {:unknown_adapter, other}}
    end
  end

  @doc """
  Puts a value in the cache (no TTL).
  """
  def put(cache_name, key, value) do
    case adapter() do
      Cachex ->
        Cachex.put(cache_name, key, value)

      WandererNotifier.Cache.ETSCache ->
        WandererNotifier.Cache.ETSCache.put(key, value, table: cache_name)

      WandererNotifier.Cache.SimpleETSCache ->
        WandererNotifier.Cache.SimpleETSCache.put(key, value)

      other ->
        {:error, {:unknown_adapter, other}}
    end
  end

  @doc """
  Deletes a value from the cache.
  """
  def del(cache_name, key) do
    case adapter() do
      Cachex ->
        Cachex.del(cache_name, key)

      WandererNotifier.Cache.ETSCache ->
        case WandererNotifier.Cache.ETSCache.delete(key, table: cache_name) do
          :ok -> {:ok, true}
          error -> error
        end

      WandererNotifier.Cache.SimpleETSCache ->
        case WandererNotifier.Cache.SimpleETSCache.delete(key) do
          :ok -> {:ok, true}
          error -> error
        end

      other ->
        {:error, {:unknown_adapter, other}}
    end
  end

  @doc """
  Clears all values from the cache.
  """
  def clear(cache_name) do
    case adapter() do
      Cachex ->
        Cachex.clear(cache_name)

      WandererNotifier.Cache.ETSCache ->
        case WandererNotifier.Cache.ETSCache.clear(table: cache_name) do
          :ok -> {:ok, true}
          error -> error
        end

      WandererNotifier.Cache.SimpleETSCache ->
        case WandererNotifier.Cache.SimpleETSCache.clear() do
          :ok -> {:ok, true}
          error -> error
        end

      other ->
        {:error, {:unknown_adapter, other}}
    end
  end
end
