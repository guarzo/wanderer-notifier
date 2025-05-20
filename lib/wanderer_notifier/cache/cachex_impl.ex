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

  # Cache name is stored as a module attribute but still retrieved at runtime
  # to allow different environments to use different caches
  @default_cache_name :wanderer_cache

  # Cache name is retrieved at runtime to allow different environments to use different caches
  defp cache_name, do: Application.get_env(:wanderer_notifier, :cache_name, @default_cache_name)

  @impl true
  def init_batch_logging do
    AppLogger.init_batch_logger()
  end

  @impl true
  def get(key) do
    case key do
      nil ->
        AppLogger.cache_warn("Attempted to get with nil key")
        {:error, :nil_key}

      _ ->
        try do
          case Cachex.get(cache_name(), key) do
            {:ok, nil} ->
              AppLogger.cache_debug("Cache key not found", key: key)
              {:error, :not_found}

            {:ok, value} ->
              AppLogger.cache_debug("Cache key found", key: key)
              {:ok, value}

            {:error, reason} ->
              AppLogger.cache_error("Error retrieving cache key",
                key: key,
                error: inspect(reason)
              )

              {:error, reason}
          end
        rescue
          e ->
            AppLogger.cache_error("Error getting value",
              key: key,
              error: Exception.message(e)
            )

            {:error, {:exception, Exception.message(e)}}
        end
    end
  end

  @impl true
  def set(key, value, ttl) do
    case {key, value} do
      {nil, _} ->
        AppLogger.cache_warn("Attempted to set with nil key")
        {:error, :nil_key}

      {_, nil} ->
        AppLogger.cache_warn("Attempted to set nil value",
          key: key
        )

        {:error, :nil_value}

      _ ->
        AppLogger.cache_debug("Setting cache value with TTL",
          key: key,
          ttl_seconds: ttl
        )

        case validate_ttl(key, ttl) do
          {:ok, validated_ttl} ->
            perform_cache_set(key, value, validated_ttl)

          {:error, reason} ->
            # Fall back to a nil TTL if validation fails
            AppLogger.cache_warn("Using nil TTL due to validation error",
              key: key,
              reason: reason
            )

            perform_cache_set(key, value, nil)
        end
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

  # Helper function to validate TTL value
  defp validate_ttl(key, ttl) do
    cond do
      is_nil(ttl) ->
        {:ok, nil}

      (is_integer(ttl) or is_float(ttl)) and ttl > 0 ->
        {:ok, trunc(ttl)}

      (is_integer(ttl) or is_float(ttl)) and ttl <= 0 ->
        AppLogger.cache_warn("Non-positive TTL value provided, using default",
          key: key,
          ttl_seconds: ttl
        )

        {:error, :invalid_ttl}

      true ->
        AppLogger.cache_warn("Invalid TTL value provided, using default",
          key: key,
          ttl_seconds: ttl
        )

        {:error, :invalid_ttl}
    end
  end

  # Helper function to perform the actual cache set operation
  defp perform_cache_set(key, value, validated_ttl) do
    try do
      result =
        if is_nil(validated_ttl) do
          Cachex.put(cache_name(), key, value)
        else
          Cachex.put(cache_name(), key, value, ttl: :timer.seconds(validated_ttl))
        end

      case result do
        {:ok, true} ->
          :ok

        {:ok, false} ->
          AppLogger.cache_warn("Cache set operation returned false",
            key: key,
            ttl: validated_ttl
          )

          {:error, :set_failed}

        {:error, reason} ->
          AppLogger.cache_error("Cache set operation failed",
            key: key,
            ttl: validated_ttl,
            error: inspect(reason)
          )

          {:error, reason}
      end
    rescue
      e ->
        AppLogger.cache_error("Error in perform_cache_set",
          key: key,
          ttl: validated_ttl,
          error: Exception.message(e)
        )

        {:error, e}
    end
  end

  @impl true
  def put(key, value) do
    case key do
      nil ->
        AppLogger.cache_warn("Attempted to put with nil key")
        {:error, :nil_key}

      _ ->
        # For high-volume sets, we'll use batch logging
        AppLogger.count_batch_event(:cache_set, %{key_pattern: get_key_pattern(key)})

        case value do
          nil ->
            AppLogger.cache_warn("Attempted to cache nil value",
              key: key
            )

            {:error, :nil_value}

          _ ->
            try do
              case Cachex.put(cache_name(), key, value) do
                {:ok, true} ->
                  AppLogger.cache_debug("Cache put successful", key: key)
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
        end
    end
  end

  @impl true
  def delete(key) do
    case key do
      nil ->
        AppLogger.cache_warn("Attempted to delete with nil key")
        {:error, :nil_key}

      _ ->
        try do
          AppLogger.cache_debug("Deleting cache key", key: key)

          case Cachex.del(cache_name(), key) do
            {:ok, true} ->
              AppLogger.cache_debug("Cache key deleted successfully", key: key)
              :ok

            {:ok, false} ->
              AppLogger.cache_debug("Cache key not found", key: key)
              {:error, :not_found}

            {:error, reason} ->
              AppLogger.cache_error("Error deleting cache key",
                key: key,
                error: inspect(reason)
              )

              {:error, reason}
          end
        rescue
          e ->
            AppLogger.cache_error("Error deleting key",
              key: key,
              error: Exception.message(e)
            )

            {:error, e}
        end
    end
  end

  @impl true
  def clear do
    try do
      AppLogger.cache_info("Clearing entire cache")

      case Cachex.clear(cache_name()) do
        {:ok, true} ->
          AppLogger.cache_info("Cache cleared successfully")
          :ok

        # Cache was already empty
        {:ok, false} ->
          AppLogger.cache_debug("Cache was already empty")
          :ok

        {:error, reason} ->
          AppLogger.cache_error("Error clearing cache",
            error: inspect(reason)
          )

          {:error, reason}
      end
    rescue
      e ->
        AppLogger.cache_error("Error clearing cache",
          error: Exception.message(e)
        )

        {:error, e}
    end
  end

  @impl true
  def get_and_update(key, update_fun) do
    case key do
      nil ->
        AppLogger.cache_warn("Attempted to get_and_update with nil key")
        {:error, :nil_key}

      _ ->
        try do
          # Pass update_fun directly to Cachex.get_and_update
          case Cachex.get_and_update(cache_name(), key, fn current ->
                 case update_fun.(current) do
                   {current, new} -> {current, new}
                   nil -> {nil, nil}
                 end
               end) do
            {:ok, {current, new}} ->
              {:ok, {current, new}}

            {:error, reason} ->
              AppLogger.cache_error("Error in get_and_update operation",
                key: key,
                error: inspect(reason)
              )

              {:error, reason}
          end
        rescue
          e ->
            AppLogger.cache_error("Error in get_and_update",
              key: key,
              error: Exception.message(e)
            )

            {:error, e}
        end
    end
  end

  @impl true
  def get_kill(kill_id) when is_binary(kill_id) or is_integer(kill_id) do
    try do
      id = to_string(kill_id)
      key = Keys.zkill_recent_kill(id)

      case get(key) do
        {:ok, nil} ->
          AppLogger.cache_debug("Kill not found in cache",
            kill_id: id
          )

          {:error, :not_found}

        {:ok, value} when is_map(value) ->
          {:ok, value}

        {:ok, _} ->
          AppLogger.cache_warn("Invalid kill value in cache",
            kill_id: id
          )

          {:error, :invalid_value}

        {:error, reason} ->
          AppLogger.cache_error("Error retrieving kill from cache",
            kill_id: id,
            error: inspect(reason)
          )

          {:error, reason}
      end
    rescue
      e ->
        AppLogger.cache_error("Error processing kill_id",
          kill_id: kill_id,
          error: Exception.message(e)
        )

        {:error, :invalid_kill_id}
    end
  end

  @impl true
  def mget(keys) when is_list(keys) do
    case keys do
      [] -> {:ok, []}
      _ -> process_mget_keys(keys)
    end
  end

  # Process a list of keys for mget
  defp process_mget_keys(keys) do
    try do
      valid_keys = filter_valid_keys(keys)
      results = process_keys_in_batches(valid_keys)
      {:ok, format_mget_results(results)}
    rescue
      e ->
        AppLogger.cache_error("Error in mget",
          keys: keys,
          error: Exception.message(e)
        )

        {:error, {:exception, Exception.message(e)}}
    end
  end

  # Filter out nil keys and log warning if any were found
  defp filter_valid_keys(keys) do
    valid_keys = Enum.reject(keys, &is_nil/1)

    if length(valid_keys) != length(keys) do
      AppLogger.cache_warn("Some keys were nil in mget",
        total_keys: length(keys),
        valid_keys: length(valid_keys)
      )
    end

    valid_keys
  end

  # Process keys in batches with timeout
  defp process_keys_in_batches(keys) do
    batch_size = 10
    timeout = 5000

    keys
    |> Enum.chunk_every(batch_size)
    |> Enum.flat_map(&process_batch(&1, timeout))
  end

  # Process a single batch of keys
  defp process_batch(batch, timeout) do
    tasks = Enum.map(batch, &create_get_task/1)

    Enum.map(tasks, fn task ->
      case Task.yield(task, timeout) || Task.shutdown(task) do
        {:ok, result} -> result
        nil -> {:error, :timeout}
      end
    end)
  end

  # Create an async task for getting a single key
  defp create_get_task(key) do
    Task.async(fn ->
      case Cachex.get(cache_name(), key) do
        {:ok, value} -> {:ok, {key, value}}
        {:error, reason} -> {:error, {key, reason}}
      end
    end)
  end

  # Format the results to match our get/1 format
  defp format_mget_results(results) do
    Enum.map(results, &format_single_result/1)
  end

  # Format a single result
  defp format_single_result(result) do
    case result do
      {:ok, {_key, nil}} ->
        {:error, :not_found}

      {:ok, {_key, value}} ->
        {:ok, value}

      {:error, {_key, reason}} ->
        AppLogger.cache_error("Error retrieving value in mget",
          error: inspect(reason)
        )

        {:error, reason}

      {:error, :timeout} ->
        AppLogger.cache_error("Timeout retrieving value in mget")
        {:error, :timeout}

      other ->
        AppLogger.cache_error("Unexpected result in mget",
          result: inspect(other)
        )

        {:error, :unexpected_result}
    end
  end

  @impl true
  def get_recent_kills do
    case get(Keys.zkill_recent_kills()) do
      {:ok, kills} when is_list(kills) and length(kills) > 0 ->
        kills

      {:ok, _} ->
        AppLogger.cache_debug("No recent kills found in cache")
        []

      {:error, reason} ->
        AppLogger.cache_error("Error retrieving recent kills",
          error: inspect(reason)
        )

        []
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

  defp get_key_pattern({prefix, _}) when is_atom(prefix), do: "#{prefix}:"
  defp get_key_pattern({prefix, _}) when is_integer(prefix), do: "#{prefix}:"
  defp get_key_pattern(key), do: inspect(key)
end
