defmodule WandererNotifier.Data.Cache do
  @moduledoc """
  Cache interface that delegates to the configured cache implementation.
  """

  @doc """
  Gets a value from the cache by key.
  """
  def get(key) do
    impl().get(key)
  end

  @doc """
  Sets a value in the cache with an optional TTL.
  """
  def set(key, value, ttl \\ nil) do
    impl().set(key, value, ttl)
  end

  @doc """
  Puts a value in the cache with an optional TTL.
  """
  def put(key, value, ttl \\ nil) do
    impl().put(key, value, ttl)
  end

  @doc """
  Deletes a value from the cache by key.
  """
  def delete(key) do
    impl().delete(key)
  end

  @doc """
  Clears all values from the cache.
  """
  def clear do
    impl().clear()
  end

  @doc """
  Gets and updates a value atomically.
  """
  def get_and_update(key, update_fn) do
    impl().get_and_update(key, update_fn)
  end

  # Private helper to get the configured cache implementation
  defp impl do
    Application.get_env(:wanderer_notifier, :cache_impl, WandererNotifier.ETSCache)
  end
end
