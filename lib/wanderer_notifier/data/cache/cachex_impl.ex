defmodule WandererNotifier.Data.Cache.CachexImpl do
  @moduledoc """
  Cachex-based implementation of the cache behaviour.
  """

  @behaviour WandererNotifier.Data.Cache.CacheBehaviour

  alias WandererNotifier.Logger.Logger, as: AppLogger

  @cache_name Application.compile_env(:wanderer_notifier, :cache_name, :wanderer_cache)

  # Initialize batch logging for cache operations
  def init_batch_logging do
    AppLogger.init_batch_logger()
  end

  @impl true
  def get(key) do
    case Cachex.get(@cache_name, key) do
      {:ok, value} when not is_nil(value) ->
        # Use batch logging for cache hits
        AppLogger.count_batch_event(:cache_hit, %{key_pattern: get_key_pattern(key)})
        value

      _ ->
        # Use batch logging for cache misses
        AppLogger.count_batch_event(:cache_miss, %{key_pattern: get_key_pattern(key)})
        handle_nil_result(key)
    end
  rescue
    e ->
      AppLogger.cache_error("Error retrieving value",
        key: key,
        error: Exception.message(e)
      )

      nil
  end

  @impl true
  def set(key, value, ttl) do
    AppLogger.cache_debug("Setting cache value with TTL",
      key: key,
      ttl_seconds: ttl
    )

    Cachex.put(@cache_name, key, value, ttl: ttl * 1000)
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
    current = get(key)
    {get_value, new_value} = update_fun.(current)
    result = put(key, new_value)
    {get_value, result}
  rescue
    e ->
      AppLogger.cache_error("Error in get_and_update operation",
        key: key,
        error: Exception.message(e)
      )

      {nil, {:error, e}}
  end

  defp handle_nil_result(key) do
    if key in ["map:systems", "map:characters"], do: [], else: nil
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
