defmodule WandererNotifier.Processing.Killmail.Cache do
  @moduledoc """
  Manages caching of killmail data.

  - Stores recent kills in the cache repository
  - Provides retrieval methods for cached kills
  - Maintains a list of kill IDs for quick access
  """

  alias WandererNotifier.Cache.Repository, as: CacheRepo
  alias WandererNotifier.Data.Killmail
  alias WandererNotifier.Logger.Logger, as: AppLogger

  # Cache keys and configuration
  @recent_kills_cache_key "zkill:recent_kills"
  @max_recent_kills 10
  # 1 hour TTL for cached kills
  @kill_ttl 3600
  @system_names_cache_key :system_names_cache

  @doc """
  Initialize the cache.
  Sets up the system names cache in process dictionary.
  """
  def init do
    # Initialize system names cache
    Process.put(@system_names_cache_key, %{})
    AppLogger.kill_debug("Kill cache initialized")
  end

  @doc """
  Updates the cache with a new kill.

  ## Parameters
  - killmail: The killmail struct to cache
  """
  def update_recent_kills(%Killmail{} = killmail) do
    # Add enhanced logging to trace cache updates
    AppLogger.kill_debug("Storing Killmail struct in shared cache repository")

    kill_id = killmail.killmail_id

    # Store the individual kill by ID
    individual_key = "#{@recent_kills_cache_key}:#{kill_id}"

    # Store the Killmail struct directly - no need to convert again
    CacheRepo.set(individual_key, killmail, @kill_ttl)

    # Now update the list of recent kill IDs
    update_recent_kill_ids(kill_id)

    AppLogger.kill_debug("Stored kill #{kill_id} in shared cache repository")
    :ok
  end

  @doc """
  Gets a list of recent kills from the cache.
  """
  def get_recent_kills do
    AppLogger.kill_debug("Retrieving recent kills from shared cache repository")

    # First get the list of recent kill IDs
    kill_ids = CacheRepo.get(@recent_kills_cache_key) || []
    AppLogger.kill_debug("Found #{length(kill_ids)} recent kill IDs in cache")

    # Then fetch each kill by its ID
    recent_kills =
      Enum.map(kill_ids, fn id ->
        key = "#{@recent_kills_cache_key}:#{id}"
        kill_data = CacheRepo.get(key)

        if kill_data do
          # Log successful retrieval
          AppLogger.kill_debug("Successfully retrieved kill #{id} from cache")
          kill_data
        else
          # Log cache miss
          AppLogger.kill_warning("Failed to retrieve kill #{id} from cache (expired or missing)")
          nil
        end
      end)
      # Remove any nils from the list
      |> Enum.filter(&(&1 != nil))

    AppLogger.kill_debug("Retrieved #{length(recent_kills)} cached kills from shared repository")

    recent_kills
  end

  @doc """
  Gets a system name from the cache or from the API.

  ## Parameters
  - system_id: The ID of the system to get name for

  ## Returns
  - System name or nil if not found
  """
  def get_system_name(_system_id) do
    # This function would be moved here from the main KillProcessor
    # It would handle looking up system names from the cache
    # and falling back to the API if not found
    nil
  end

  # Private functions

  # Update the list of recent kill IDs in the cache
  defp update_recent_kill_ids(new_kill_id) do
    # Get current list of kill IDs from the cache
    kill_ids = CacheRepo.get(@recent_kills_cache_key) || []

    # Add the new ID to the front
    updated_ids =
      [new_kill_id | kill_ids]
      # Remove duplicates
      |> Enum.uniq()
      # Keep only the most recent ones
      |> Enum.take(@max_recent_kills)

    # Update the cache
    CacheRepo.set(@recent_kills_cache_key, updated_ids, @kill_ttl)

    AppLogger.kill_debug("Updated recent kill IDs in cache - now has #{length(updated_ids)} IDs")
  end
end
