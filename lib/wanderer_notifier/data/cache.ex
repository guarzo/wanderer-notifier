defmodule WandererNotifier.Data.Cache do
  @moduledoc """
  Cache interface that delegates to the configured cache implementation.
  """

  alias WandererNotifier.Logger.Logger, as: AppLogger

  @doc """
  Gets a value from the cache by key.
  """
  def get(key) do
    AppLogger.cache_debug("Cache get operation", %{key: key})
    result = impl().get(key)

    if is_nil(result) do
      AppLogger.cache_debug("Cache miss", %{key: key})
    else
      AppLogger.cache_debug("Cache hit", %{key: key})
    end

    result
  end

  @doc """
  Sets a value in the cache with an optional TTL.
  """
  def set(key, value, ttl \\ nil) do
    AppLogger.cache_debug("Cache set operation", %{key: key, ttl: ttl})
    impl().set(key, value, ttl)
  end

  @doc """
  Puts a value in the cache with an optional TTL.
  """
  def put(key, value, ttl \\ nil) do
    AppLogger.cache_debug("Cache put operation", %{key: key, ttl: ttl})
    impl().put(key, value, ttl)
  end

  @doc """
  Deletes a value from the cache by key.
  """
  def delete(key) do
    AppLogger.cache_debug("Cache delete operation", %{key: key})
    impl().delete(key)
  end

  @doc """
  Clears all values from the cache.
  """
  def clear do
    AppLogger.cache_info("Clearing entire cache")
    impl().clear()
  end

  @doc """
  Gets and updates a value atomically.
  """
  def get_and_update(key, update_fn) do
    AppLogger.cache_debug("Cache get_and_update operation", %{key: key})
    impl().get_and_update(key, update_fn)
  end

  # Private helper to get the configured cache implementation
  defp impl do
    Application.get_env(:wanderer_notifier, :cache_impl, WandererNotifier.ETSCache)
  end
end
