defmodule WandererNotifier.Cache.Repository do
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
        Logger.warning("Failed to create cache directory at #{cache_dir}: #{inspect(reason)}. Falling back to temporary directory.")
        # Fall back to a temporary directory that should be writable
        cache_dir = System.tmp_dir!() |> Path.join("wanderer_notifier_cache")
        File.mkdir_p!(cache_dir)
        Logger.info("Using fallback cache directory: #{cache_dir}")
    end

    # Configure Cachex with optimized settings
    cachex_options = [
      # Set a higher limit for maximum entries (default is often too low)
      limit: 10000,

      # Configure memory limits (in bytes) - 256MB
      max_size: 256 * 1024 * 1024,

      # Policy for when the cache hits the limit
      policy: Cachex.Policy.LRW,

      # Enable statistics for better monitoring
      stats: true,

      # Set fallback function for cache misses
      fallback: &handle_cache_miss/1
    ]

    # Start Cachex
    result = Cachex.start_link(@cache_name, cachex_options)
    Logger.info("Cache repository started with result: #{inspect(result)}")

    # Start the cache monitoring process
    GenServer.start_link(__MODULE__, [cache_dir], name: __MODULE__)

    result
  end

  # Helper function to determine the appropriate cache directory
  defp determine_cache_dir do
    # Get the configured cache directory
    configured_dir = Application.get_env(:wanderer_notifier, :cache_dir, "/app/data/cache")

    cond do
      # Check if we're in a dev container
      String.contains?(File.cwd!(), "dev-container") or String.contains?(File.cwd!(), "workspaces") ->
        # Use a directory in the current workspace
        Path.join(File.cwd!(), "tmp/cache")

      # Otherwise use the configured directory (for production)
      true ->
        configured_dir
    end
  end

  # Fallback function for cache misses
  defp handle_cache_miss(key) do
    Logger.debug("[CacheRepo] Cache miss handled by fallback for key: #{key}")
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
    {:ok, %{last_systems_count: 0, last_characters_count: 0, consecutive_failures: 0, cache_dir: cache_dir}}
  end

  # Fallback for when no cache_dir is passed (for backward compatibility)
  @impl true
  def init(_) do
    # Determine cache directory
    cache_dir = determine_cache_dir()
    # Schedule the first cache check
    schedule_cache_check()
    {:ok, %{last_systems_count: 0, last_characters_count: 0, consecutive_failures: 0, cache_dir: cache_dir}}
  end

  @impl true
  def handle_info(:check_cache, state) do
    # Check if cache is available
    cache_available = case Cachex.stats(@cache_name) do
      {:ok, stats} ->
        Logger.debug("[CacheRepo] Cache stats: #{inspect(stats)}")
        true
      error ->
        Logger.error("[CacheRepo] Failed to get cache stats: #{inspect(error)}")
        false
    end

    new_state = if not cache_available do
      consecutive_failures = state.consecutive_failures + 1
      Logger.error("[CacheRepo] Cache is no longer available! This may indicate a serious issue. Consecutive failures: #{consecutive_failures}")

      # After 3 consecutive failures, attempt recovery
      if consecutive_failures >= 3 do
        Logger.warning("[CacheRepo] Attempting to recover cache after #{consecutive_failures} consecutive failures")
        attempt_cache_recovery(state.cache_dir)
        %{state | consecutive_failures: 0}
      else
        %{state | consecutive_failures: consecutive_failures}
      end
    else
      # Reset failure counter if cache is available
      %{state | consecutive_failures: 0}
    end

    # Get systems count - don't initialize empty arrays here
    systems = get("map:systems") || []
    systems_count = length(systems)

    # Get characters count - don't initialize empty arrays here
    characters = get("map:characters") || []
    characters_count = length(characters)

    # Log if counts have changed
    if systems_count != state.last_systems_count do
      Logger.info("[CacheRepo] Systems count changed: #{state.last_systems_count} -> #{systems_count}")
    end

    if characters_count != state.last_characters_count do
      Logger.info("[CacheRepo] Characters count changed: #{state.last_characters_count} -> #{characters_count}")
    end

    # Schedule the next check
    schedule_cache_check()

    {:noreply, %{new_state | last_systems_count: systems_count, last_characters_count: characters_count}}
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

      case result do
        {:ok, value} when not is_nil(value) ->
          Logger.debug("[CacheRepo] Cache hit for key: #{key}, found #{length_of(value)} items")
          value
        {:ok, nil} ->
          # Treat nil value as a cache miss and return nil
          Logger.warning("[CacheRepo] Cache hit for key: #{key}, but value is nil")

          # Special handling for map:systems and map:characters keys
          # If the key exists but the value is nil, reinitialize it with an empty array
          if key in ["map:systems", "map:characters"] and exists_result == {:ok, true} do
            Logger.warning("[CacheRepo] Reinitializing #{key} with empty array")
            Cachex.put(@cache_name, key, [])
            []
          else
            nil
          end
        {:error, error} ->
          Logger.error("[CacheRepo] Cache error for key: #{key}, error: #{inspect(error)}")
          nil
        _ ->
          Logger.debug("[CacheRepo] Cache miss for key: #{key}")
          nil
      end
    end)
  end

  @doc """
  Sets a value in the cache with a TTL (time to live).
  """
  def set(key, value, ttl) do
    retry_with_backoff(fn ->
      Logger.debug("[CacheRepo] Setting value for key: #{key} with TTL: #{ttl}, storing #{length_of(value)} items")

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
          Logger.error("[CacheRepo] Failed to set cache for key: #{key}, result: #{inspect(result)}")
          {:error, result}
      end
    end)
  end

  @doc """
  Puts a value in the cache without a TTL.
  """
  def put(key, value) do
    retry_with_backoff(fn ->
      Logger.debug("[CacheRepo] Putting value for key: #{key} without TTL, storing #{length_of(value)} items")
      result = Cachex.put(@cache_name, key, value)
      case result do
        {:ok, true} ->
          Logger.debug("[CacheRepo] Successfully put cache for key: #{key}")
          {:ok, true}
        _ ->
          Logger.error("[CacheRepo] Failed to put cache for key: #{key}, result: #{inspect(result)}")
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

  # Helper functions for logging
  defp length_of(value) when is_list(value), do: length(value)
  defp length_of(value) when is_map(value), do: map_size(value)
  defp length_of(value) when is_binary(value), do: String.length(value)
  defp length_of(_), do: "N/A"

  # Retry function with exponential backoff
  defp retry_with_backoff(fun, retries \\ nil) do
    retries = retries || Timings.max_retries()
    case fun.() do
      {:error, _} when retries > 0 ->
        Process.sleep(Timings.retry_delay())
        retry_with_backoff(fun, retries - 1)
      result ->
        result
    end
  end

  # Attempt to recover the cache by restarting it
  defp attempt_cache_recovery(_cache_dir) do
    Logger.warning("[CacheRepo] Attempting to restart the cache...")

    # Stop the existing cache process
    case Process.whereis(@cache_name) do
      pid when is_pid(pid) ->
        Process.exit(pid, :shutdown)
        Logger.info("[CacheRepo] Successfully stopped the existing cache")
      nil ->
        Logger.warning("[CacheRepo] Cache process not found, proceeding with start")
    end

    # Configure Cachex with optimized settings
    cachex_options = [
      # Set a higher limit for maximum entries (default is often too low)
      limit: 10000,

      # Configure memory limits (in bytes) - 256MB
      max_size: 256 * 1024 * 1024,

      # Policy for when the cache hits the limit
      policy: Cachex.Policy.LRW,

      # Enable statistics for better monitoring
      stats: true,

      # Set fallback function for cache misses
      fallback: &handle_cache_miss/1
    ]

    # Start a new cache
    case Cachex.start(@cache_name, cachex_options) do
      {:ok, _pid} ->
        Logger.info("[CacheRepo] Successfully restarted the cache")

        # Trigger a refresh of critical data
        Process.send_after(WandererNotifier.Service, :force_refresh_cache, 1000)
      error ->
        Logger.error("[CacheRepo] Failed to restart the cache: #{inspect(error)}")
    end
  end
end
