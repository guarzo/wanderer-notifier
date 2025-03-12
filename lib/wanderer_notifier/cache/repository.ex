defmodule WandererNotifier.Cache.Repository do
  @moduledoc """
  Cachex repository for WandererNotifier.
  Provides a simple interface for caching data with optional TTL.
  """
  use GenServer
  require Logger

  @cache_name :wanderer_notifier_cache

  def start_link(_args \\ []) do
    Logger.info("Starting WandererNotifier cache repository...")
    Cachex.start_link(@cache_name, [])
  end

  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      type: :worker,
      restart: :permanent,
      shutdown: 500
    }
  end

  @impl true
  def init(init_arg) do
    {:ok, init_arg}
  end

  @doc """
  Gets a value from the cache by key.
  Returns nil if the key doesn't exist.
  """
  def get(key) do
    case Cachex.get(@cache_name, key) do
      {:ok, value} -> value
      _ -> nil
    end
  end

  @doc """
  Sets a value in the cache with a TTL (time to live).
  """
  def set(key, value, ttl) do
    Cachex.put(@cache_name, key, value, ttl: ttl)
  end

  @doc """
  Puts a value in the cache without a TTL.
  """
  def put(key, value) do
    Cachex.put(@cache_name, key, value)
  end

  @doc """
  Deletes a value from the cache by key.
  """
  def delete(key) do
    Cachex.del(@cache_name, key)
  end

  @doc """
  Clears all values from the cache.
  """
  def clear do
    Cachex.clear(@cache_name)
  end

  @doc """
  Checks if a key exists in the cache.
  """
  def exists?(key) do
    case Cachex.exists?(@cache_name, key) do
      {:ok, exists} -> exists
      _ -> false
    end
  end

  @doc """
  Gets the TTL (time to live) for a key.
  Returns nil if the key doesn't exist or has no TTL.
  """
  def ttl(key) do
    case Cachex.ttl(@cache_name, key) do
      {:ok, ttl} -> ttl
      _ -> nil
    end
  end
end
