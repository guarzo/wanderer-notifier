defmodule WandererNotifier.Data.Cache.Repository do
  @moduledoc """
  Cachex repository for WandererNotifier.
  Provides a simple interface for caching data with optional TTL.
  """
  use GenServer
  require Logger
  alias WandererNotifier.Config.Timings

  @cache_name :wanderer_notifier_cache

  def start_link(_args \\ []) do
    Logger.info("Starting WandererNotifier cache repository...")

    # Ensure cache directory exists
    # Use a path that works in both dev container and production
    cache_dir = determine_cache_dir()

    # Ensure the directory exists
    case File.mkdir_p(cache_dir) do
      :ok ->
        Logger.info("Using cache directory: #{cache_dir}")

      {:error, reason} ->
        Logger.warning(
          "Failed to create cache directory at #{cache_dir}: #{inspect(reason)}. Falling back to temporary directory."
        )

        # Fall back to a temporary directory that should be writable
        cache_dir = System.tmp_dir!() |> Path.join("wanderer_notifier_cache")
        File.mkdir_p!(cache_dir)
        Logger.info("Using fallback cache directory: #{cache_dir}")
    end

    # Configure Cachex with optimized settings
    cachex_options = [
      # Set a higher limit for maximum entries (default is often too low)
      limit: 10_000,

      # Configure memory limits (in bytes) - 256MB
      max_size: 256 * 1024 * 1024,

      # Policy for when the cache hits the limit
      policy: Cachex.Policy.LRW,

      # Enable statistics for better monitoring
      stats: true,

      # Set fallback function for cache misses
      fallback: &handle_cache_miss/1
    ]

    # Start Cachex with explicit name to ensure it can be referenced by the GenServer
    cachex_result =
      case Cachex.start_link(@cache_name, cachex_options) do
        {:ok, pid} = result ->
          Logger.info("Cache storage started successfully with pid: #{inspect(pid)}")
          result

        {:error, {:already_started, pid}} ->
          Logger.warning("Cache already started with pid: #{inspect(pid)}")
          {:ok, pid}

        error ->
          Logger.error("Failed to start cache: #{inspect(error)}")
          error
      end

    # Only start the GenServer monitor if Cachex started successfully
    case cachex_result do
      {:ok, _cachex_pid} ->
        # Start the cache monitoring process
        GenServer.start_link(__MODULE__, [cache_dir], name: __MODULE__)

      error ->
        # Return the error so supervision can handle it properly
        error
    end
  end

  # Helper function to determine the appropriate cache directory
  defp determine_cache_dir do
    # Get the configured cache directory
    configured_dir = Application.get_env(:wanderer_notifier, :cache_dir, "/app/data/cache")

    cond do
      # Check if we're in a dev container
      String.contains?(File.cwd!(), "dev-container") or
          String.contains?(File.cwd!(), "workspaces") ->
        # Use a directory in the current workspace
        Path.join(File.cwd!(), "tmp/cache")

      # Otherwise use the configured directory (for production)
      true ->
        configured_dir
    end
  end

  # Fallback function for cache misses
  defp handle_cache_miss(key) do
    # Different logging levels based on key type for better diagnostics
    cond do
      # Critical system keys should be error logged as they generally shouldn't be missing
      key in ["license_status", "core_config"] ->
        Logger.error("[CacheRepo] Critical cache miss for key: #{key}")

      # Application state keys get warning level - might indicate state issue
      String.starts_with?(key, "state:") || String.starts_with?(key, "app:") ->
        Logger.warning("[CacheRepo] Application state cache miss for key: #{key}")

      # Map data keys get info level - could be normal during startup
      String.starts_with?(key, "map:") ->
        Logger.info("[CacheRepo] Map data cache miss for key: #{key}")

      # All other keys get debug level logging
      true ->
        Logger.debug("[CacheRepo] Cache miss handled by fallback for key: #{key}")
    end

    # Return the same result for all cases to maintain backward compatibility
    {:ignore, nil}
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
  def init([cache_dir]) do
    # Schedule the first cache check
    schedule_cache_check()

    {:ok,
     %{
       last_systems_count: 0,
       last_characters_count: 0,
       consecutive_failures: 0,
       cache_dir: cache_dir,
       last_purge: :os.system_time(:second)
     }}
  end

  # Fallback for when no cache_dir is passed (for backward compatibility)
  @impl true
  def init(_) do
    schedule_cache_check()

    {:ok,
     %{
       last_systems_count: 0,
       last_characters_count: 0,
       consecutive_failures: 0,
       cache_dir: nil,
       last_purge: :os.system_time(:second)
     }}
  end

  # Handle cache check message
  @impl true
  def handle_info(:check_cache, state) do
    # Get cache stats
    stats_result = Cachex.stats(@cache_name)

    # Handle stats result, which could be {:ok, stats} or {:error, :stats_disabled}
    case stats_result do
      {:ok, stats} ->
        Logger.debug("[CacheRepo] Cache stats: #{inspect(stats)}")

      {:error, :stats_disabled} ->
        Logger.debug("[CacheRepo] Cache stats are disabled")

      other_error ->
        Logger.warning("[CacheRepo] Failed to get cache stats: #{inspect(other_error)}")
    end

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

    # Periodically purge expired entries (once per hour)
    last_purge = Map.get(state, :last_purge, 0)
    current_time = :os.system_time(:second)

    state =
      if current_time - last_purge > 3600 do
        Logger.info("[CacheRepo] Performing hourly cache purge")
        purge_expired_entries()
        Map.put(state, :last_purge, current_time)
      else
        state
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
      Logger.debug("[CacheRepo] Getting value for key: #{key}")
      result = Cachex.get(@cache_name, key)
      Logger.debug("[CacheRepo] Raw result from Cachex: #{inspect(result)}")

      # Check if the key exists in the cache
      exists_result = Cachex.exists?(@cache_name, key)
      Logger.debug("[CacheRepo] Key exists check: #{inspect(exists_result)}")

      # Check TTL for the key
      ttl_result = Cachex.ttl(@cache_name, key)
      Logger.debug("[CacheRepo] TTL for key: #{inspect(ttl_result)}")

      process_get_result(key, result, exists_result)
    end)
  end

  @doc """
  Gets a value from the cache, updates it with the provided function, and stores the result.
  The update function should accept the current value and return {new_value, result}.
  The TTL is preserved for the key.
  """
  def get_and_update(key, update_fn) do
    retry_with_backoff(fn ->
      Logger.debug("[CacheRepo] Getting and updating value for key: #{key}")

      # Get the current value and TTL
      current_value = get(key)
      current_ttl = ttl(key)

      # Apply the update function to get the new value
      {new_value, result} = update_fn.(current_value)

      # Store the new value with the same TTL if it exists
      if current_ttl && current_ttl > 0 do
        # Convert from milliseconds to seconds for our set function
        ttl_seconds = div(current_ttl, 1000)
        set(key, new_value, ttl_seconds)
      else
        # No TTL, just store the value permanently
        put(key, new_value)
      end

      # Return the result from the update function
      result
    end)
  end

  @doc """
  Gets multiple values from the cache by keys in a batch operation.
  Returns a map of {key => value} pairs. Keys that don't exist will have nil values.
  """
  def get_many(keys) when is_list(keys) do
    retry_with_backoff(fn ->
      Logger.debug("[CacheRepo] Batch getting #{length(keys)} keys")

      # Implement our own batch get since Cachex doesn't provide get_many
      results =
        Enum.map(keys, fn key ->
          case Cachex.get(@cache_name, key) do
            {:ok, value} -> {key, value}
            _ -> {key, nil}
          end
        end)

      # Convert results to a map for easier access
      Map.new(results)
    end)
  end

  # Helper functions to process get results
  defp process_get_result(key, {:ok, value}, _exists_result) when not is_nil(value) do
    Logger.debug("[CacheRepo] Cache hit for key: #{key}, found #{length_of(value)} items")
    value
  end

  defp process_get_result(key, {:ok, nil}, {:ok, true}) do
    # Handle special keys that should initialize as empty lists when they exist but have nil value
    if special_collection_key?(key) do
      init_empty_collection(key)
    else
      handle_nil_value(key)
    end
  end

  defp process_get_result(key, {:ok, nil}, _exists_result) do
    handle_nil_value(key)
  end

  defp process_get_result(key, {:error, error}, _exists_result) do
    Logger.error("[CacheRepo] Cache error for key: #{key}, error: #{inspect(error)}")
    nil
  end

  defp process_get_result(key, _result, _exists_result) do
    Logger.debug("[CacheRepo] Cache miss for key: #{key}")
    nil
  end

  # Checks if the key is a special collection key that should initialize as empty list
  defp special_collection_key?(key) do
    key in ["map:systems", "map:characters"]
  end

  # Initialize an empty collection for special keys
  defp init_empty_collection(key) do
    Logger.debug("[CacheRepo] Initializing #{key} with empty array")
    Cachex.put(@cache_name, key, [])
    []
  end

  # Handle nil values based on key type
  defp handle_nil_value(key) do
    if String.starts_with?(key, "static_info:") do
      Logger.debug("[CacheRepo] Cache miss for static info key: #{key}")
    else
      Logger.debug("[CacheRepo] Cache hit for key: #{key}, but value is nil")
    end

    nil
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
      Logger.debug("[CacheRepo] TTL in milliseconds: #{ttl_ms}")

      result = Cachex.put(@cache_name, key, value, ttl: ttl_ms)

      case result do
        {:ok, true} ->
          # Verify the TTL was set correctly
          ttl_result = Cachex.ttl(@cache_name, key)
          Logger.debug("[CacheRepo] Verified TTL after set: #{inspect(ttl_result)}")

          Logger.debug("[CacheRepo] Successfully set cache for key: #{key}")
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
          Logger.debug("[CacheRepo] Successfully put cache for key: #{key}")
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
      Logger.info("[CacheRepo] Deleting key: #{key} from cache")
      Cachex.del(@cache_name, key)
    end)
  end

  @doc """
  Clears all values from the cache.
  """
  def clear do
    retry_with_backoff(fn ->
      Logger.warning("[CacheRepo] Clearing entire cache")
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

  @doc """
  Purges expired cache entries to free up memory.
  """
  def purge_expired_entries do
    Logger.info("[CacheRepo] Purging expired cache entries")

    try do
      case Cachex.purge(@cache_name) do
        {:ok, count} ->
          Logger.info("[CacheRepo] Successfully purged #{count} expired entries from cache")
          {:ok, count}

        error ->
          Logger.error("[CacheRepo] Failed to purge cache: #{inspect(error)}")
          error
      end
    rescue
      e ->
        Logger.error("[CacheRepo] Error during cache purge: #{inspect(e)}")
        {:error, e}
    end
  end

  # Retry a function with exponential backoff
  defp retry_with_backoff(fun, retries \\ Timings.max_retries()) do
    try do
      fun.()
    rescue
      e ->
        Logger.error("[CacheRepo] Error in cache operation: #{inspect(e)}")

        if retries <= 0 do
          Logger.error("[CacheRepo] Max retries reached, giving up")
          {:error, e}
        else
          Logger.warning("[CacheRepo] Retrying after error (#{retries} retries left)")
          Process.sleep(Timings.retry_delay())
          retry_with_backoff(fun, retries - 1)
        end
    catch
      :exit, reason ->
        Logger.error("[CacheRepo] Exit in cache operation: #{inspect(reason)}")

        if retries <= 0 do
          Logger.error("[CacheRepo] Max retries reached, giving up")
          {:error, reason}
        else
          Logger.warning("[CacheRepo] Retrying after exit (#{retries} retries left)")
          Process.sleep(Timings.retry_delay())
          retry_with_backoff(fun, retries - 1)
        end

      result ->
        result
    end
  end

  # Helper function to safely get the length of a value
  defp length_of(value) when is_list(value), do: length(value)
  defp length_of(value) when is_map(value), do: map_size(value)
  defp length_of(value) when is_binary(value), do: byte_size(value)
  defp length_of(_), do: 0
end
