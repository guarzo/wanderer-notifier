defmodule WandererNotifier.Data.Cache.Repository do
  @moduledoc """
  GenServer implementation for the cache repository.
  Provides a centralized interface for cache operations.
  """

  use GenServer
  require Logger
  alias WandererNotifier.Config.Cache, as: CacheConfig
  alias WandererNotifier.Config.Timings
  alias WandererNotifier.Logger.Logger, as: AppLogger

  # Use the cache name from configuration
  @cache_name CacheConfig.get_cache_name()

  # -- STARTUP AND INITIALIZATION --

  def start_link(_args) do
    # Initialize the cache with default options
    cachex_options = [
      stats: true
    ]

    # Start Cachex with the configured name and options
    case Cachex.start_link(@cache_name, cachex_options) do
      {:ok, pid} -> {:ok, pid}
      {:error, {:already_started, pid}} -> {:ok, pid}
      error -> error
    end
  end

  # -- PRIVATE HELPERS --

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
  def init([cache_dir]) do
    # Schedule the first cache check
    schedule_cache_check()

    {:ok,
     %{
       last_systems_count: 0,
       last_characters_count: 0,
       consecutive_failures: 0,
       cache_dir: cache_dir
     }}
  end

  # Fallback for when no cache_dir is passed (for backward compatibility)
  @impl true
  def init(_) do
    schedule_cache_check()

    {:ok,
     %{last_systems_count: 0, last_characters_count: 0, consecutive_failures: 0, cache_dir: nil}}
  end

  # Handle cache check message
  @impl true
  def handle_info(:check_cache, state) do
    # Get cache stats
    {:ok, stats} = Cachex.stats(@cache_name)
    AppLogger.cache_debug("[CacheRepo] Cache stats: #{inspect(stats)}")

    # Check systems and characters counts
    systems = get("map:systems") || []
    characters = get("map:characters") || []

    systems_count = length(systems)
    characters_count = length(characters)

    # Log changes in counts
    if systems_count != state.last_systems_count do
      Logger.info(
        "[CacheRepo] Systems count changed: #{state.last_systems_count} -> #{systems_count}"
      )
    end

    if characters_count != state.last_characters_count do
      Logger.info(
        "[CacheRepo] Characters count changed: #{state.last_characters_count} -> #{characters_count}"
      )
    end

    # Schedule the next check
    schedule_cache_check()

    {:noreply,
     %{state | last_systems_count: systems_count, last_characters_count: characters_count}}
  end

  defp schedule_cache_check do
    Process.send_after(self(), :check_cache, Timings.cache_check_interval())
  end

  @doc """
  Gets a value from the cache by key.
  Returns nil if the key doesn't exist.
  """
  def get(key) do
    retry_with_backoff(fn ->
      AppLogger.cache_debug("[CacheRepo] Getting value for key: #{key}")
      result = Cachex.get(@cache_name, key)
      AppLogger.cache_debug("[CacheRepo] Raw result from Cachex: #{inspect(result)}")

      # Check if the key exists in the cache
      exists_result = Cachex.exists?(@cache_name, key)
      AppLogger.cache_debug("[CacheRepo] Key exists check: #{inspect(exists_result)}")

      # Check TTL for the key
      ttl_result = Cachex.ttl(@cache_name, key)
      AppLogger.cache_debug("[CacheRepo] TTL for key: #{inspect(ttl_result)}")

      case result do
        {:ok, value} when not is_nil(value) ->
          AppLogger.cache_debug(
            "[CacheRepo] Cache hit for key: #{key}, found #{length_of(value)} items"
          )

          value

        {:ok, nil} ->
          handle_nil_result(key, exists_result)

        {:error, error} ->
          AppLogger.cache_error(
            "[CacheRepo] Cache error for key: #{key}, error: #{inspect(error)}"
          )

          nil

        _ ->
          AppLogger.cache_debug("[CacheRepo] Cache miss for key: #{key}")
          nil
      end
    end)
  end

  # Handle nil results from cache to reduce nesting in get/1
  defp handle_nil_result(key, exists_result) do
    # Special handling for map:systems and map:characters keys
    if key in ["map:systems", "map:characters"] and exists_result == {:ok, true} do
      # For these keys, initialize with empty array without warning
      AppLogger.cache_debug("[CacheRepo] Initializing #{key} with empty array")
      Cachex.put(@cache_name, key, [])
      []
    else
      log_cache_miss(key)
      nil
    end
  end

  # Log cache misses appropriately based on key type
  defp log_cache_miss(key) do
    if String.starts_with?(key, "static_info:") do
      AppLogger.cache_debug("[CacheRepo] Cache miss for static info key: #{key}")
    else
      AppLogger.cache_debug("[CacheRepo] Cache hit for key: #{key}, but value is nil")
    end
  end

  @doc """
  Sets a value in the cache with a TTL (time to live).
  """
  def set(key, value, ttl) do
    retry_with_backoff(fn ->
      Logger.debug(
        "[CacheRepo] Setting value for key: #{key} with TTL: #{ttl}, storing #{length_of(value)} items"
      )

      # Convert TTL from seconds to milliseconds for Cachex
      ttl_ms = ttl * 1000
      AppLogger.cache_debug("[CacheRepo] TTL in milliseconds: #{ttl_ms}")

      result = Cachex.put(@cache_name, key, value, ttl: ttl_ms)

      case result do
        {:ok, true} ->
          # Verify the TTL was set correctly
          ttl_result = Cachex.ttl(@cache_name, key)
          AppLogger.cache_debug("[CacheRepo] Verified TTL after set: #{inspect(ttl_result)}")

          AppLogger.cache_debug("[CacheRepo] Successfully set cache for key: #{key}")
          {:ok, true}

        _ ->
          Logger.error(
            "[CacheRepo] Failed to set cache for key: #{key}, result: #{inspect(result)}"
          )

          {:error, result}
      end
    end)
  end

  @doc """
  Puts a value in the cache without a TTL.
  """
  def put(key, value) do
    retry_with_backoff(fn ->
      Logger.debug(
        "[CacheRepo] Putting value for key: #{key} without TTL, storing #{length_of(value)} items"
      )

      result = Cachex.put(@cache_name, key, value)

      case result do
        {:ok, true} ->
          AppLogger.cache_debug("[CacheRepo] Successfully put cache for key: #{key}")
          {:ok, true}

        _ ->
          Logger.error(
            "[CacheRepo] Failed to put cache for key: #{key}, result: #{inspect(result)}"
          )

          {:error, result}
      end
    end)
  end

  @doc """
  Deletes a value from the cache by key.
  """
  def delete(key) do
    retry_with_backoff(fn ->
      AppLogger.cache_info("[CacheRepo] Deleting key: #{key} from cache")
      Cachex.del(@cache_name, key)
    end)
  end

  @doc """
  Clears all values from the cache.
  """
  def clear do
    retry_with_backoff(fn ->
      AppLogger.cache_warn("[CacheRepo] Clearing entire cache")
      Cachex.clear(@cache_name)
    end)
  end

  @doc """
  Checks if a key exists in the cache.
  """
  def exists?(key) do
    retry_with_backoff(fn ->
      case Cachex.exists?(@cache_name, key) do
        {:ok, exists} -> exists
        _ -> false
      end
    end)
  end

  @doc """
  Gets the TTL (time to live) for a key.
  Returns nil if the key doesn't exist or has no TTL.
  """
  def ttl(key) do
    retry_with_backoff(fn ->
      case Cachex.ttl(@cache_name, key) do
        {:ok, ttl} -> ttl
        _ -> nil
      end
    end)
  end

  # Retry a function with exponential backoff
  defp retry_with_backoff(fun, retries \\ Timings.max_retries()) do
    fun.()
  rescue
    e ->
      AppLogger.cache_error("[CacheRepo] Error in cache operation: #{inspect(e)}")

      if retries <= 0 do
        AppLogger.cache_error("[CacheRepo] Max retries reached, giving up")
        {:error, e}
      else
        AppLogger.cache_warn("[CacheRepo] Retrying after error (#{retries} retries left)")
        Process.sleep(Timings.retry_delay())
        retry_with_backoff(fun, retries - 1)
      end
  catch
    :exit, reason ->
      AppLogger.cache_error("[CacheRepo] Exit in cache operation: #{inspect(reason)}")

      if retries <= 0 do
        AppLogger.cache_error("[CacheRepo] Max retries reached, giving up")
        {:error, reason}
      else
        AppLogger.cache_warn("[CacheRepo] Retrying after exit (#{retries} retries left)")
        Process.sleep(Timings.retry_delay())
        retry_with_backoff(fun, retries - 1)
      end

    result ->
      result
  end

  # Helper function to safely get the length of a value
  defp length_of(value) when is_list(value), do: length(value)
  defp length_of(value) when is_map(value), do: map_size(value)
  defp length_of(value) when is_binary(value), do: byte_size(value)
  defp length_of({:ok, value}) when is_list(value), do: length(value)
  defp length_of({:ok, _value}), do: 1
  defp length_of(_), do: 0

  @doc """
  Updates cache after a successful database write to ensure consistency.
  This should be called after any database operation that might affect cached data.

  ## Parameters
    - key: The cache key to update
    - value: The new value to store in cache
    - ttl: Optional time-to-live in seconds

  ## Returns
    - {:ok, true} if cache was updated successfully
    - {:error, reason} if there was an error
  """
  def update_after_db_write(key, value, ttl \\ nil) do
    retry_with_backoff(fn ->
      Logger.debug(
        "[CacheRepo] Updating cache after DB write for key: #{key}, storing #{length_of(value)} items"
      )

      result =
        if ttl do
          # Set with TTL if provided
          ttl_ms = ttl * 1000
          Cachex.put(@cache_name, key, value, ttl: ttl_ms)
        else
          # Otherwise just put without TTL
          Cachex.put(@cache_name, key, value)
        end

      case result do
        {:ok, true} ->
          AppLogger.cache_debug(
            "[CacheRepo] Successfully updated cache after DB write for key: #{key}"
          )

          {:ok, true}

        _ ->
          Logger.error(
            "[CacheRepo] Failed to update cache after DB write for key: #{key}, result: #{inspect(result)}"
          )

          {:error, result}
      end
    end)
  end

  @doc """
  Gets a value from the cache and updates it atomically.
  This is useful for making concurrent updates to cached values.

  ## Parameters
    - key: The cache key to update
    - update_fun: A function that takes the current value and returns {get_value, new_value}
    - ttl: Optional time-to-live in seconds for the updated value

  ## Returns
    - {get_value, result} where result is the result of the update operation
  """
  def get_and_update(key, update_fun, ttl \\ nil) do
    retry_with_backoff(fn ->
      AppLogger.cache_debug("[CacheRepo] Atomic get_and_update for key: #{key}")

      # First get the current value
      current_value = get(key)

      # Apply the update function
      {get_value, new_value} = update_fun.(current_value)

      # Update the cache
      result =
        if ttl do
          set(key, new_value, ttl)
        else
          put(key, new_value)
        end

      {get_value, result}
    end)
  end

  @doc """
  Synchronizes a cache key with database via provided function.
  The db_read_fun should fetch data from database and return {:ok, value} or {:error, reason}.
  Optionally accepts a TTL in seconds.

  ## Returns
    - {:ok, value} if synchronized successfully
    - {:error, reason} if there was an error
  """
  def sync_with_db(key, db_read_fun, ttl \\ nil) do
    retry_with_backoff(fn ->
      AppLogger.cache_debug("[CacheRepo] Synchronizing cache key '#{key}' with database")

      # Read from database
      case db_read_fun.() do
        {:ok, value} ->
          # Update cache with value from database
          update_cache_from_db(key, value, ttl)

        {:error, reason} = error ->
          AppLogger.cache_error(
            "[CacheRepo] Database read failed during cache sync: #{inspect(reason)}"
          )

          error
      end
    end)
  end

  # Helper to update cache with value from database
  defp update_cache_from_db(key, value, ttl) do
    # Choose appropriate cache update method based on TTL
    result = if ttl, do: set(key, value, ttl), else: put(key, value)

    # Handle result of cache update
    handle_cache_update_result(key, value, result)
  end

  # Handle the result of a cache update operation
  defp handle_cache_update_result(key, value, {:ok, true}) do
    AppLogger.cache_debug(
      "[CacheRepo] Successfully synchronized cache key '#{key}' with database"
    )

    {:ok, value}
  end

  defp handle_cache_update_result(_key, _value, error) do
    AppLogger.cache_error(
      "[CacheRepo] Failed to update cache during database sync: #{inspect(error)}"
    )

    {:error, :cache_update_failed}
  end

  @doc """
  Gets recent kills from the cache.
  """
  def get_recent_kills do
    case get("recent_kills") do
      nil -> []
      kills -> kills
    end
  end
end
