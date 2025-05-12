defmodule WandererNotifier.Cache.CachexImpl do
  @moduledoc """
  Cachex-based implementation of the cache behaviour.
  Provides a high-performance cache implementation using Cachex.

  Features:
  - TTL support
  - Atomic operations
  - Batch operation support
  - Comprehensive error handling
  - Logging and monitoring
  """

  @behaviour WandererNotifier.Cache.Behaviour

  alias WandererNotifier.Logger.Logger, as: AppLogger
  alias WandererNotifier.Cache.Keys

  # Cache name is retrieved at runtime to allow different environments to use different caches
  defp cache_name, do: Application.get_env(:wanderer_notifier, :cache_name, :wanderer_cache)

  @impl true
  def init_batch_logging do
    AppLogger.init_batch_logger()
  end

  @impl true
  def get(key) do
    case Cachex.get(cache_name(), key) do
      {:ok, nil} -> {:error, :not_found}
      {:ok, value} -> {:ok, value}
      {:error, reason} -> {:error, reason}
    end
  rescue
    e ->
      AppLogger.cache_error("Error getting value",
        key: key,
        error: Exception.message(e)
      )

      {:error, e}
  end

  @impl true
  def set(key, value, ttl) do
    AppLogger.cache_debug("Setting cache value with TTL",
      key: key,
      ttl_seconds: ttl
    )

    validated_ttl = validate_ttl(key, ttl)
    perform_cache_set(key, value, validated_ttl)
  rescue
    e ->
      AppLogger.cache_error("Error setting value with TTL",
        key: key,
        ttl_seconds: ttl,
        error: Exception.message(e)
      )

      {:error, e}
  end

  # Helper function to validate TTL value
  defp validate_ttl(key, ttl) do
    cond do
      is_nil(ttl) ->
        nil

      is_integer(ttl) and ttl > 0 ->
        ttl

      is_integer(ttl) and ttl <= 0 ->
        AppLogger.cache_warn("Non-positive TTL value provided, using default",
          key: key,
          ttl_seconds: ttl
        )

        nil

      true ->
        AppLogger.cache_warn("Invalid TTL value provided, using default",
          key: key,
          ttl_seconds: ttl
        )

        nil
    end
  end

  # Helper function to perform the actual cache set operation
  defp perform_cache_set(key, value, validated_ttl) do
    result =
      if is_nil(validated_ttl) do
        Cachex.put(cache_name(), key, value)
      else
        Cachex.put(cache_name(), key, value, ttl: :timer.seconds(validated_ttl))
      end

    case result do
      {:ok, true} -> :ok
      {:ok, false} -> {:error, :set_failed}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def put(key, value) do
    # For high-volume sets, we'll use batch logging
    AppLogger.count_batch_event(:cache_set, %{key_pattern: get_key_pattern(key)})

    case Cachex.put(cache_name(), key, value) do
      {:ok, true} ->
        :ok

      {:ok, false} ->
        # Log the failure but return a more specific reason
        AppLogger.cache_warn("Cache put returned false",
          key: key
        )

        {:error, :cachex_put_returned_false}

      {:error, reason} ->
        # Return the actual error reason from Cachex for better debugging
        AppLogger.cache_error("Cache put failed with specific reason",
          key: key,
          error: inspect(reason)
        )

        {:error, reason}
    end
  rescue
    e ->
      AppLogger.cache_error("Error setting value",
        key: key,
        error: Exception.message(e)
      )

      {:error, {:exception, Exception.message(e)}}
  end

  @impl true
  def delete(key) do
    AppLogger.cache_debug("Deleting cache key", key: key)

    case Cachex.del(cache_name(), key) do
      {:ok, true} -> :ok
      {:ok, false} -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
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

    case Cachex.clear(cache_name()) do
      {:ok, true} -> :ok
      {:ok, false} -> {:error, :clear_failed}
      {:error, reason} -> {:error, reason}
    end
  rescue
    e ->
      AppLogger.cache_error("Error clearing cache",
        error: Exception.message(e)
      )

      {:error, e}
  end

  @impl true
  def get_and_update(key, update_fun) do
    try do
      # Pass update_fun directly to Cachex.get_and_update
      Cachex.get_and_update(cache_name(), key, update_fun)
    rescue
      e ->
        AppLogger.cache_error("Error in get_and_update",
          key: key,
          error: Exception.message(e)
        )

        {:error, e}
    end
  end

  @impl true
  def get_recent_kills do
    case get(Keys.zkill_recent_kills()) do
      {:ok, kills} -> kills
      _ -> []
    end
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
