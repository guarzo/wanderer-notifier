defmodule WandererNotifier.Cache.CachexImpl do
  @moduledoc """
  Cachex-based implementation of the cache behaviour.
  """

  @behaviour WandererNotifier.Cache.CacheBehaviour

  alias WandererNotifier.Logger.Logger, as: AppLogger

  @cache_name Application.compile_env(:wanderer_notifier, :cache_name, :wanderer_cache)

  # Initialize batch logging for cache operations
  def init_batch_logging do
    AppLogger.init_batch_logger()
  end

  @impl true
  def get(key) do
    case Cachex.get(@cache_name, key) do
      {:ok, nil} -> {:error, :not_found}
      {:ok, value} -> {:ok, value}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def set(key, value, ttl) do
    AppLogger.cache_debug("Setting cache value with TTL",
      key: key,
      ttl_seconds: ttl
    )

    if is_nil(ttl) do
      Cachex.put(@cache_name, key, value)
    else
      Cachex.put(@cache_name, key, value, ttl: :timer.seconds(ttl))
    end
  rescue
    e ->
      AppLogger.cache_error("Error setting value with TTL",
        key: key,
        ttl_seconds: ttl,
        error: Exception.message(e)
      )

      {:error, e}
  end

  @impl true
  def put(key, value) do
    # For high-volume sets, we'll use batch logging
    AppLogger.count_batch_event(:cache_set, %{key_pattern: get_key_pattern(key)})
    Cachex.put(@cache_name, key, value)
  rescue
    e ->
      AppLogger.cache_error("Error setting value",
        key: key,
        error: Exception.message(e)
      )

      {:error, e}
  end

  @impl true
  def delete(key) do
    AppLogger.cache_debug("Deleting cache key", key: key)
    Cachex.del(@cache_name, key)
  rescue
    e ->
      AppLogger.cache_error("Error deleting key",
        key: key,
        error: Exception.message(e)
      )

      {:error, e}
  end

  @impl true
  def clear do
    AppLogger.cache_info("Clearing entire cache")
    Cachex.clear(@cache_name)
  rescue
    e ->
      AppLogger.cache_error("Error clearing cache",
        error: Exception.message(e)
      )

      {:error, e}
  end

  @impl true
  def get_and_update(key, update_fun) do
    Cachex.get_and_update(@cache_name, key, fn
      nil ->
        {current, updated} = update_fun.(nil)
        {current, updated}

      existing ->
        {current, updated} = update_fun.(existing)
        {current, updated}
    end)
  end

  # Helper to extract a pattern from the key for batch logging
  defp get_key_pattern(key) when is_binary(key) do
    # If key has a colon, take the part before the colon, otherwise use as-is
    case String.split(key, ":", parts: 2) do
      [prefix, _] -> "#{prefix}:"
      _ -> key
    end
  end

  defp get_key_pattern(key), do: inspect(key)
end
