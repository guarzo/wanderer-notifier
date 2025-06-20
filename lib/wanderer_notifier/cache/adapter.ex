defmodule WandererNotifier.Cache.Adapter do
  @moduledoc """
  Provides a unified interface for different cache adapters.

  This module abstracts the underlying cache implementation,
  allowing the application to switch between Cachex (production)
  and ETSCache (testing) transparently.
  """

  alias WandererNotifier.Cache.Config
  alias WandererNotifier.Cache.ETSCache

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

      ETSCache ->
        ETSCache.get(key, table: cache_name)

      other ->
        {:error, {:unknown_adapter, other}}
    end
  end

  @doc """
  Sets a value in the cache with a TTL.
  """
  def set(cache_name, key, value, ttl \\ nil) do
    ttl = normalize_ttl(ttl)
    do_set(adapter(), cache_name, key, value, ttl)
  end

  defp normalize_ttl(nil) do
    case Config.ttl_for(:default) do
      :infinity -> :infinity
      ttl_ms -> :timer.seconds(ttl_ms)
    end
  end

  defp normalize_ttl(:infinity), do: :infinity
  defp normalize_ttl(ttl_val), do: ttl_val

  defp do_set(Cachex, cache_name, key, value, ttl) do
    # Convert :infinity to nil for Cachex (nil means no expiry)
    cachex_ttl = if ttl == :infinity, do: nil, else: ttl
    Cachex.put(cache_name, key, value, ttl: cachex_ttl)
  end

  defp do_set(ETSCache, cache_name, key, value, ttl) do
    ETSCache.set(key, value, ttl, table: cache_name)
  end

  defp do_set(other, _cache_name, _key, _value, _ttl) do
    {:error, {:unknown_adapter, other}}
  end

  @doc """
  Puts a value in the cache (no TTL).
  """
  def put(cache_name, key, value) do
    case adapter() do
      Cachex ->
        Cachex.put(cache_name, key, value)

      ETSCache ->
        ETSCache.put(key, value, table: cache_name)

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

      ETSCache ->
        case ETSCache.delete(key, table: cache_name) do
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

      ETSCache ->
        case ETSCache.clear(table: cache_name) do
          :ok -> {:ok, true}
          error -> error
        end

      other ->
        {:error, {:unknown_adapter, other}}
    end
  end
end
