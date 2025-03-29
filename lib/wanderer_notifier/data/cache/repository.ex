defmodule WandererNotifier.Data.Cache.Repository do
  @moduledoc """
  Cachex repository for WandererNotifier.
  Provides a simple interface for caching data with optional TTL.
  """
  use GenServer
  require Logger
  alias WandererNotifier.Logger, as: AppLogger
  alias WandererNotifier.Config.Cache

  @cache_name :wanderer_notifier_cache

  def start_link(_args \\ []) do
    AppLogger.cache_info("Starting cache repository")

    # Ensure cache directory exists
    # Use a path that works in both dev container and production
    cache_dir = determine_cache_dir()

    # Ensure the directory exists with more robust error handling
    cache_dir = ensure_cache_directory(cache_dir)

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

    # Add disk persistence only if we have a valid cache directory
    cachex_options =
      if cache_dir do
        disk_options = [
          disk: [
            path: cache_dir,
            # 1 minute
            sync_interval: 60_000,
            sync_on_terminate: true
          ]
        ]

        Keyword.merge(cachex_options, disk_options)
      else
        cachex_options
      end

    # Start Cachex with explicit name to ensure it can be referenced by the GenServer
    cachex_result =
      case Cachex.start_link(@cache_name, cachex_options) do
        {:ok, pid} = result ->
          AppLogger.cache_info("Cache storage started successfully", pid: inspect(pid))
          result

        {:error, {:already_started, pid}} ->
          AppLogger.cache_warn("Cache already started", pid: inspect(pid))
          {:ok, pid}

        error ->
          AppLogger.cache_error("Failed to start cache", error: inspect(error))
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

  # Helper to ensure the cache directory exists with robust error handling
  defp ensure_cache_directory(cache_dir) do
    AppLogger.cache_info("Creating/verifying cache directory", path: cache_dir)

    # Make sure parent directories exist
    parent_dir = Path.dirname(cache_dir)

    _parent_result =
      if parent_dir != cache_dir do
        AppLogger.cache_debug("Creating parent directory structure", path: parent_dir)
        File.mkdir_p(parent_dir)
      else
        :ok
      end

    # Now try to create the actual cache directory
    case make_directory(cache_dir) do
      :ok ->
        # Success, use the specified directory
        AppLogger.cache_info("Using cache directory", path: cache_dir)
        cache_dir

      {:error, reason} ->
        # Failed to create or use the specified directory
        AppLogger.cache_warn("Failed to create cache directory",
          path: cache_dir,
          reason: inspect(reason)
        )

        # Fall back to temporary directory as a last resort
        tmp_dir = Path.join(System.tmp_dir!(), "wanderer_notifier_cache")
        make_directory(tmp_dir)
        AppLogger.cache_info("Using fallback cache directory", path: tmp_dir)
        tmp_dir

      error ->
        # Unexpected error
        AppLogger.cache_error("Unexpected error creating cache directory",
          path: cache_dir,
          error: inspect(error)
        )

        nil
    end
  end

  # Attempt to create a directory
  defp make_directory(dir) do
    File.mkdir_p(dir)
  end

  # Helper function to determine the appropriate cache directory
  defp determine_cache_dir do
    Cache.get_cache_dir()
  end

  # GENSERVER CALLBACKS

  @impl true
  def init(_args) do
    # Initialize state
    initial_state = %{
      last_check_time: 0,
      last_systems_count: 0,
      last_characters_count: 0,
      last_error: nil,
      last_error_time: 0
    }

    # Schedule first cache check
    schedule_cache_check()

    # Schedule initial cache purge
    schedule_cache_purge()

    {:ok, initial_state}
  end

  # Handle cache check message
  @impl true
  def handle_info(:check_cache, state) do
    # Get cache stats
    stats_result = Cachex.stats(@cache_name)

    # Handle stats result, which could be {:ok, stats} or {:error, :stats_disabled}
    case stats_result do
      {:ok, stats} ->
        AppLogger.cache_debug("Cache stats", stats: inspect(stats))

      {:error, :stats_disabled} ->
        AppLogger.cache_debug("Cache stats are disabled")

      other_error ->
        AppLogger.cache_warn("Failed to get cache stats", error: inspect(other_error))
    end

    # Check systems and characters counts
    systems = get("map:systems") || []
    characters = get("map:characters") || []

    systems_count = length(systems)
    characters_count = length(characters)

    # Log changes in counts with descriptive messages
    if systems_count != state.last_systems_count do
      AppLogger.cache_info(
        "Systems count changed: #{state.last_systems_count} → #{systems_count}",
        %{
          previous_count: state.last_systems_count,
          new_count: systems_count
        }
      )
    end

    if characters_count != state.last_characters_count do
      AppLogger.cache_info(
        "Characters count changed: #{state.last_characters_count} → #{characters_count}",
        %{
          previous_count: state.last_characters_count,
          new_count: characters_count
        }
      )
    end

    # Schedule the next check
    schedule_cache_check()

    # Return updated state
    {:noreply,
     %{
       state
       | last_check_time: System.os_time(:second),
         last_systems_count: systems_count,
         last_characters_count: characters_count
     }}
  end

  @impl true
  def handle_info(:purge_cache, state) do
    # Schedule next purge
    schedule_cache_purge()

    # Perform the purge operation
    try do
      # Get cache stats for monitoring
      case get_cachex_stats() do
        {:ok, stats} ->
          AppLogger.cache_debug("Cache statistics", stats: inspect(stats))

        {:error, :stats_disabled} ->
          AppLogger.cache_debug("Cache statistics are disabled")

        other_error ->
          AppLogger.cache_warn("Failed to get cache statistics", error: inspect(other_error))
      end

      # Log purge operation at info level
      AppLogger.cache_info("Performing hourly cache purge")

      # Perform the actual purge
      purge_expired_entries()
    rescue
      e ->
        # Update state with error
        updated_state = %{
          state
          | last_error: Exception.message(e),
            last_error_time: System.os_time(:second)
        }

        {:noreply, updated_state}
    end

    {:noreply, state}
  end

  @impl true
  def handle_info(msg, state) do
    # Log unhandled messages at warning level
    AppLogger.cache_warn("Received unexpected message", message: inspect(msg))
    {:noreply, state}
  end

  defp schedule_cache_check do
    Process.send_after(self(), :check_cache, 60_000)
  end

  @doc """
  Gets a value from the cache by key.
  Returns nil if the key doesn't exist.

  Important: This function always unwraps {:ok, value} tuples to return just the value.
  """
  def get(key) do
    retry_with_backoff(fn ->
      # Use a sampling approach to reduce debug logs (only log ~1% of gets)
      should_log = :rand.uniform(100) <= 1

      # Log the get operation if sampled
      log_get_operation(key, should_log)

      # Get the value from cache
      result = Cachex.get(@cache_name, key)

      # Log detailed cache info if sampled
      log_cache_details(key, result, should_log)

      # Process the result
      process_cache_result(key, result, should_log)
    end)
  end

  # Log the get operation if sampled
  defp log_get_operation(key, true) do
    AppLogger.cache_debug("Getting value (sampled 1%)", key: key)
  end

  defp log_get_operation(_key, false), do: :ok

  # Log detailed cache info if sampled
  defp log_cache_details(key, result, true) do
    # Only check exists and TTL if we're already sampling this request
    exists_result = Cachex.exists?(@cache_name, key)
    ttl_result = Cachex.ttl(@cache_name, key)

    AppLogger.cache_debug("Cache details (sampled)",
      key: key,
      result: inspect(result),
      exists: inspect(exists_result),
      ttl: inspect(ttl_result)
    )
  end

  defp log_cache_details(_key, _result, false), do: :ok

  # Process the result of a cache get operation
  defp process_cache_result(key, {:ok, value}, _should_log) when not is_nil(value) do
    # Don't log individual cache hits, but count them for batch logging
    key_pattern = extract_key_pattern(key)

    WandererNotifier.Logger.BatchLogger.count_event(:cache_hit, %{
      key_pattern: key_pattern
    })

    value
  end

  defp process_cache_result(key, {:ok, nil}, should_log) do
    handle_nil_result(key, should_log)
  end

  defp process_cache_result(key, {:error, error}, _should_log) do
    # Always log errors
    AppLogger.cache_error("Cache error", key: key, error: inspect(error))
    nil
  end

  defp process_cache_result(key, _other_result, should_log) do
    # Count cache misses for batch logging
    key_pattern = extract_key_pattern(key)

    WandererNotifier.Logger.BatchLogger.count_event(:cache_miss, %{
      key_pattern: key_pattern
    })

    # Log miss only if we're sampling
    if should_log do
      AppLogger.cache_debug("Cache miss (sampled)", key: key)
    end

    nil
  end

  @doc """
  Gets a value from the cache, updates it with the provided function, and stores the result.
  The update function should accept the current value and return {new_value, result}.
  The TTL is preserved for the key.
  """
  def get_and_update(key, update_fn) do
    # Use the atomic transaction for consistency
    Cachex.transaction(@cache_name, [key], fn worker ->
      # Get the current value
      current_value = Cachex.get!(worker, key)

      # Apply the update function to get the new value and return value
      {return_value, new_value} = update_fn.(current_value)

      # Store the new value
      Cachex.put(worker, key, new_value)

      # Return the function's return value
      return_value
    end)
  end

  @doc """
  Gets and updates a value in the cache with an optional TTL.
  Accepts a key, an update function, and a TTL value in seconds.
  The update function should take the current value and return a tuple {return_value, new_value}.
  """
  def get_and_update(key, update_fn, ttl) do
    # Use the atomic transaction for consistency
    Cachex.transaction(@cache_name, [key], fn worker ->
      # Get the current value
      current_value = Cachex.get!(worker, key)

      # Apply the update function to get the new value and return value
      {return_value, new_value} = update_fn.(current_value)

      # Store the new value with TTL
      Cachex.put(worker, key, new_value, ttl: :timer.seconds(ttl))

      # Return the function's return value
      return_value
    end)
  end

  @doc """
  Gets multiple values from the cache by keys in a batch operation.
  Returns a map of {key => value} pairs. Keys that don't exist will have nil values.
  """
  def get_many(keys) when is_list(keys) do
    retry_with_backoff(fn ->
      AppLogger.cache_debug("Batch getting keys", count: length(keys))

      # Implement our own batch get since Cachex doesn't provide get_many
      results = Enum.map(keys, &get_single_key/1)

      # Convert results to a map for easier access
      Map.new(results)
    end)
  end

  # Helper function to get a single key from the cache
  defp get_single_key(key) do
    case Cachex.get(@cache_name, key) do
      {:ok, value} -> {key, value}
      _ -> {key, nil}
    end
  end

  # Handle fallback for cache misses with different strategies for different key types
  defp handle_cache_miss(key) do
    cond do
      # Critical application state - should always be set before accessed
      critical_key?(key) ->
        AppLogger.cache_error("Critical cache miss", key: key)
        nil

      # Application state that might not be set yet
      state_key?(key) ->
        AppLogger.cache_warn("Application state cache miss", key: key)
        nil

      # Map data that can be initialized as empty
      map_key?(key) ->
        AppLogger.cache_info("Map data cache miss", key: key)
        %{}

      # Arrays can be initialized as empty
      array_key?(key) ->
        AppLogger.cache_debug("Array cache miss handled by fallback", key: key)
        []

      # Default for unknown keys
      true ->
        nil
    end
  end

  # Determine if a key is critical - meaning a miss should be logged as an error
  defp critical_key?(key) do
    String.starts_with?(key, "critical:") || key in ["license_status", "core_config"]
  end

  # Determine if a key is application state that might be unset
  defp state_key?(key) do
    String.starts_with?(key, "state:") ||
      String.starts_with?(key, "app:") ||
      String.starts_with?(key, "config:")
  end

  # Determine if a key stores map data
  defp map_key?(key) do
    String.starts_with?(key, "map:") ||
      String.starts_with?(key, "data:") ||
      String.starts_with?(key, "config:")
  end

  # Determine if a key stores array data
  defp array_key?(key) do
    String.starts_with?(key, "array:") ||
      String.starts_with?(key, "list:") ||
      String.starts_with?(key, "recent:")
  end

  # Define guard-compatible macros
  defguard is_array_key(key)
           when is_binary(key) and
                  ((byte_size(key) >= 6 and binary_part(key, 0, 6) == "array:") or
                     (byte_size(key) >= 5 and binary_part(key, 0, 5) == "list:") or
                     (byte_size(key) >= 7 and binary_part(key, 0, 7) == "recent:"))

  defguard is_map_key(key)
           when is_binary(key) and
                  ((byte_size(key) >= 4 and binary_part(key, 0, 4) == "map:") or
                     (byte_size(key) >= 5 and binary_part(key, 0, 5) == "data:") or
                     (byte_size(key) >= 7 and binary_part(key, 0, 7) == "config:"))

  # Special guard for static_info keys
  defguard is_static_info_key(key)
           when is_binary(key) and
                  byte_size(key) >= 11 and
                  binary_part(key, byte_size(key) - 11, 11) == "static_info"

  @doc """
  Updates a cache entry after a cache check.
  Used by the maintenance service to populate cache from lookups.

  ## Parameters
    - key: The cache key to update
    - value: The value to set
    - ttl_seconds: TTL in seconds (optional)
  """
  def update_after_check(key, value, ttl_seconds \\ nil) do
    AppLogger.cache_info("Updating cache after check", key: key)
    set(key, value, ttl_seconds)
  end

  @doc """
  Logs cache miss statistics to help identify areas for improvement.
  """
  def log_cache_miss_statistics do
    AppLogger.cache_info("Logging cache miss statistics")

    # Get overall cache stats
    case get_cachex_stats() do
      {:ok, stats} ->
        # Calculate hit rate if there are enough operations
        total_operations = stats[:operations][:get] || 0

        if total_operations > 0 do
          hit_rate = (stats[:hits] || 0) / total_operations

          AppLogger.cache_info("Cache performance statistics",
            hit_rate_pct: Float.round(hit_rate * 100, 2),
            total_operations: total_operations,
            hits: stats[:hits] || 0,
            misses: stats[:misses] || 0
          )
        end

      _ ->
        AppLogger.cache_info("Cache statistics not available")
    end
  end

  @doc """
  Safely gets a value from the cache, logging hits/misses appropriately.

  ## Parameters
    - key: The key to retrieve

  ## Returns
    - The value if found
    - nil if not found or on error
  """
  def safe_get(key) do
    # This method should redirect to get now that we've improved that method
    # with sampling to reduce log volume
    get(key)
  end

  @doc """
  Gets a value or initializes it if it's missing.

  ## Parameters
    - key: The key to retrieve
    - default: The default value to set if the key doesn't exist
    - ttl_seconds: Optional TTL in seconds
  """
  def get_or_set(key, default, ttl_seconds \\ nil) do
    case get(key) do
      {:ok, nil} when is_array_key(key) ->
        AppLogger.cache_debug("Initializing with empty array", key: key)
        set(key, [], ttl_seconds)
        []

      {:ok, nil} when is_map_key(key) and is_static_info_key(key) ->
        AppLogger.cache_debug("Cache miss for static info", key: key)
        set(key, default, ttl_seconds)
        default

      {:ok, nil} ->
        AppLogger.cache_debug("Cache hit but value is nil", key: key)
        set(key, default, ttl_seconds)
        default

      {:ok, value} ->
        value

      _ ->
        # For any error or not found, set the default
        AppLogger.cache_debug("Setting default value",
          key: key,
          ttl_seconds: ttl_seconds
        )

        set(key, default, ttl_seconds)
        default
    end
  end

  # Schedule cache purge after 1 hour
  defp schedule_cache_purge do
    Process.send_after(self(), :purge_cache, 3_600_000)
  end

  # Get stats from Cachex
  defp get_cachex_stats do
    Cachex.stats(@cache_name)
  end

  @doc """
  Synchronizes the cache with the database.
  Takes a key, a function to read from the database, and a TTL (time-to-live) in seconds.
  The db_read_fun is a function that fetches the data from the database.
  """
  def sync_with_db(key, db_read_fun, ttl) do
    # Don't use a transaction here to avoid holding locks during DB access
    try do
      # Fetch fresh data from the database
      db_result = db_read_fun.()

      # Store the result in cache with TTL
      cache_db_result(key, db_result, ttl)
    rescue
      e ->
        AppLogger.cache_error("Error syncing cache with DB",
          key: key,
          error: Exception.message(e)
        )

        {:error, :sync_failed}
    end
  end

  # Helper to cache database query results with appropriate handling
  defp cache_db_result(key, {:ok, data}, ttl) do
    # Cache successful DB read with TTL
    Cachex.put(@cache_name, key, data, ttl: :timer.seconds(ttl))
    {:ok, data}
  end

  defp cache_db_result(_key, {:error, _} = error, _ttl) do
    # Don't cache errors, but return them
    error
  end

  defp cache_db_result(key, data, ttl) do
    # For direct returns (not {:ok, data}), cache the direct value
    Cachex.put(@cache_name, key, data, ttl: :timer.seconds(ttl))
    {:ok, data}
  end

  @doc """
  Updates the cache after a database write operation.
  This can be used to ensure cache consistency after DB writes.
  Takes a key, the new value to store, and a TTL in seconds.
  """
  def update_after_db_write(key, value, ttl) do
    # Put the new value in the cache with TTL
    Cachex.put(@cache_name, key, value, ttl: :timer.seconds(ttl))
  end

  # Purge expired entries from the cache
  defp purge_expired_entries do
    case Cachex.clear(@cache_name, expired: true) do
      {:ok, count} ->
        AppLogger.cache_info("Purged expired entries", count: count)
        {:ok, count}

      other ->
        AppLogger.cache_warn("Failed to purge expired entries", result: inspect(other))
        other
    end
  end

  # Retry a function with exponential backoff
  defp retry_with_backoff(fun, retries \\ 3) do
    try do
      fun.()
    rescue
      e ->
        AppLogger.cache_error("Error in cache operation", error: inspect(e))

        if retries <= 0 do
          AppLogger.cache_error("Max retries reached, giving up")
          {:error, e}
        else
          AppLogger.cache_warn("Retrying after error", retries_left: retries)
          Process.sleep(500)
          retry_with_backoff(fun, retries - 1)
        end
    catch
      :exit, reason ->
        AppLogger.cache_error("Exit in cache operation", reason: inspect(reason))

        if retries <= 0 do
          AppLogger.cache_error("Max retries reached, giving up")
          {:error, reason}
        else
          AppLogger.cache_warn("Retrying after exit", retries_left: retries)
          Process.sleep(500)
          retry_with_backoff(fun, retries - 1)
        end

      result ->
        result
    end
  end

  @doc """
  Sets a value in the cache with an optional TTL in seconds.
  """
  def set(key, value, ttl_seconds \\ nil) do
    # Trace logging in development for debugging
    AppLogger.cache_debug("Setting cache value", key: key, ttl: ttl_seconds)

    # Use the proper process to interact with Cachex
    case Cachex.put(@cache_name, key, value, ttl: ttl_option(ttl_seconds)) do
      {:ok, true} ->
        AppLogger.cache_debug("Cache value set successfully", key: key)
        :ok

      {:ok, false} ->
        AppLogger.cache_warn("Failed to set cache value", key: key)
        {:error, :set_failed}

      {:error, reason} ->
        AppLogger.cache_error("Error setting cache value", key: key, error: inspect(reason))
        {:error, reason}
    end
  end

  @doc """
  An alias for set/3 to maintain compatibility with code using put/3.
  """
  def put(key, value, ttl_seconds \\ nil) do
    set(key, value, ttl_seconds)
  end

  @doc """
  Checks if a key exists in the cache.
  """
  def exists?(key) do
    case Cachex.exists?(@cache_name, key) do
      {:ok, exists} ->
        exists

      {:error, reason} ->
        AppLogger.cache_error("Error checking cache key existence",
          key: key,
          error: inspect(reason)
        )

        false
    end
  end

  @doc """
  Deletes a value from the cache.
  """
  def delete(key) do
    AppLogger.cache_debug("Deleting cache value", key: key)

    case Cachex.del(@cache_name, key) do
      {:ok, _} ->
        :ok

      {:error, reason} ->
        AppLogger.cache_error("Error deleting cache value",
          key: key,
          error: inspect(reason)
        )

        {:error, reason}
    end
  end

  # Helper to format TTL option for Cachex
  defp ttl_option(nil), do: nil
  defp ttl_option(seconds) when is_integer(seconds) and seconds > 0, do: seconds * 1000
  defp ttl_option(_), do: nil

  # Handle nil results from cache - now takes a should_log parameter
  defp handle_nil_result(key, should_log) do
    # Special handling for map:systems and map:characters keys
    if key in ["map:systems", "map:characters"] do
      # For these keys, initialize with empty array without warning
      handle_empty_array_initialization(key, should_log)
    else
      # Handle regular nil results
      handle_regular_nil_result(key, should_log)
    end
  end

  # Handle empty array initialization for specific keys
  defp handle_empty_array_initialization(key, should_log) do
    if should_log do
      AppLogger.cache_debug("Initializing with empty array (sampled)", key: key)
    end

    Cachex.put(@cache_name, key, [])
    []
  end

  # Handle regular nil result cases
  defp handle_regular_nil_result(key, should_log) do
    # Only log if we're sampling this request
    if should_log do
      log_nil_result(key)
    end

    nil
  end

  # Log nil result with appropriate message based on key
  defp log_nil_result(key) do
    if String.starts_with?(key, "static_info:") do
      AppLogger.cache_debug("Cache miss for static info (sampled)", key: key)
    else
      AppLogger.cache_debug("Cache hit but value is nil (sampled)", key: key)
    end
  end

  # Extract a key pattern for grouping similar cache keys
  defp extract_key_pattern(key) when is_binary(key) do
    cond do
      # For keys with IDs embedded, extract the pattern part
      String.match?(key, ~r/^[\w\-]+:\w+:\d+$/) ->
        # Pattern for keys like "map:system:12345" -> "map:system"
        key |> String.split(":") |> Enum.take(2) |> Enum.join(":")

      # For other known key formats
      String.match?(key, ~r/^[\w\-]+:[\w\-]+$/) ->
        # Keys like "map:systems" -> return as is
        key

      # Match most prefixes
      true ->
        # Try to get the prefix part
        case String.split(key, ":", parts: 2) do
          [prefix, _] -> "#{prefix}:*"
          _ -> key
        end
    end
  end

  defp extract_key_pattern(key), do: inspect(key)
end
