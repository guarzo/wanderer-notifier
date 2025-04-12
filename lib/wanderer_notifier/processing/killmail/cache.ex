defmodule WandererNotifier.Processing.Killmail.Cache do
  @moduledoc """
  Manages caching for killmail data.

  - Stores recent kills in the cache repository
  - Provides retrieval methods for cached kills
  - Maintains a list of kill IDs for quick access

  @deprecated Use WandererNotifier.Killmail.Processing.Cache instead.
  """

  require Logger
  alias WandererNotifier.Data.Cache.Keys, as: CacheKeys
  alias WandererNotifier.Data.Cache.Repository, as: CacheRepo
  alias WandererNotifier.Logger.Logger, as: AppLogger
  alias WandererNotifier.Killmail.Processing.Cache, as: NewCache
  alias WandererNotifier.Killmail.Core.Data, as: KillmailData

  # Cache TTL values (in seconds)
  # 1 hour
  @kill_ttl 3600

  # System name cache - process dictionary for performance
  @system_names_cache_key :system_names_cache

  @doc """
  Initializes the killmail cache system.

  @deprecated Use WandererNotifier.Killmail.Processing.Cache instead.
  """
  def init do
    Logger.warning(
      "DEPRECATED: WandererNotifier.Processing.Killmail.Cache.init/0 is deprecated. " <>
        "Use WandererNotifier.Killmail.Processing.Cache instead."
    )

    # Initialize the system names cache in the process dictionary
    Process.put(@system_names_cache_key, %{})
    AppLogger.kill_debug("Kill cache initialized")
    :ok
  end

  @doc """
  Caches a killmail for quick access.

  @deprecated Use WandererNotifier.Killmail.Processing.Cache.cache/1 instead.
  """
  def cache_kill(killmail_id, killmail) when is_binary(killmail_id) or is_integer(killmail_id) do
    Logger.warning(
      "DEPRECATED: WandererNotifier.Processing.Killmail.Cache.cache_kill/2 is deprecated. " <>
        "Use WandererNotifier.Killmail.Processing.Cache.cache/1 instead."
    )

    kill_id = to_string(killmail_id)

    # Cache individual kill
    individual_key = "#{CacheKeys.zkill_recent_kills()}:#{kill_id}"

    AppLogger.cache_debug("Caching individual kill", key: individual_key)
    CacheRepo.set(individual_key, killmail, @kill_ttl)

    # Update the recent kills list
    update_recent_kills_list(kill_id)

    :ok
  end

  @doc """
  Gets a cached killmail by ID.

  @deprecated Use WandererNotifier.Killmail.Processing.Cache instead.
  """
  def get_kill(kill_id) when is_binary(kill_id) or is_integer(kill_id) do
    Logger.warning(
      "DEPRECATED: WandererNotifier.Processing.Killmail.Cache.get_kill/1 is deprecated. " <>
        "Use WandererNotifier.Killmail.Processing.Cache instead."
    )

    id = to_string(kill_id)

    # Get the list of cached kill IDs
    kill_ids = CacheRepo.get(CacheKeys.zkill_recent_kills()) || []

    # Check if this kill is in our tracked list
    if id in kill_ids do
      # Get the individual kill data
      key = "#{CacheKeys.zkill_recent_kills()}:#{id}"
      kill_data = CacheRepo.get(key)

      if kill_data do
        {:ok, kill_data}
      else
        {:error, :not_found}
      end
    else
      {:error, :not_cached}
    end
  end

  @doc """
  Gets all recent cached kills.

  @deprecated Use WandererNotifier.Killmail.Processing.Cache instead.
  """
  def get_recent_kills do
    Logger.warning(
      "DEPRECATED: WandererNotifier.Processing.Killmail.Cache.get_recent_kills/0 is deprecated. " <>
        "Use WandererNotifier.Killmail.Processing.Cache instead."
    )

    # Get the list of cached kill IDs
    kill_ids = CacheRepo.get(CacheKeys.zkill_recent_kills()) || []

    # Map through and get each kill
    kills =
      kill_ids
      |> Enum.map(fn id ->
        key = "#{CacheKeys.zkill_recent_kills()}:#{id}"
        {id, CacheRepo.get(key)}
      end)
      |> Enum.filter(fn {_id, kill} -> kill != nil end)
      |> Enum.into(%{})

    {:ok, kills}
  end

  @doc """
  Gets a system name from the cache or from the API.

  ## Parameters
  - system_id: The ID of the system to get name for

  ## Returns
  - System name or nil if not found

  @deprecated Use WandererNotifier.Killmail.Processing.Cache instead.
  """
  def get_system_name(system_id) do
    Logger.warning(
      "DEPRECATED: WandererNotifier.Processing.Killmail.Cache.get_system_name/1 is deprecated. " <>
        "Use WandererNotifier.Killmail.Processing.Cache instead."
    )

    # This function would be moved here from the main KillProcessor
    # It would handle looking up system names from the cache
    # and falling back to the API if not found
    nil
  end

  @doc """
  Checks if a killmail is already in the cache.

  ## Parameters
    - killmail_id: The killmail ID to check

  ## Returns
    - true if the killmail is in the cache
    - false otherwise

  @deprecated Use WandererNotifier.Killmail.Processing.Cache.in_cache?/1 instead.
  """
  def in_cache?(killmail_id) do
    Logger.warning(
      "DEPRECATED: WandererNotifier.Processing.Killmail.Cache.in_cache?/1 is deprecated. " <>
        "Use WandererNotifier.Killmail.Processing.Cache.in_cache?/1 instead."
    )

    NewCache.in_cache?(killmail_id)
  end

  @doc """
  Caches a killmail data struct.

  ## Parameters
    - killmail: The KillmailData struct to cache

  ## Returns
    - {:ok, cached_killmail} on success
    - {:error, reason} on failure

  @deprecated Use WandererNotifier.Killmail.Processing.Cache.cache/1 instead.
  """
  def cache(%KillmailData{} = killmail) do
    Logger.warning(
      "DEPRECATED: WandererNotifier.Processing.Killmail.Cache.cache/1 is deprecated. " <>
        "Use WandererNotifier.Killmail.Processing.Cache.cache/1 instead."
    )

    NewCache.cache(killmail)
  end

  # Private functions

  # Helper to update the recent kills list with a new kill ID
  defp update_recent_kills_list(kill_id) do
    # Get current list of kill IDs
    kill_ids = CacheRepo.get(CacheKeys.zkill_recent_kills()) || []

    # Add the new kill ID to the list (if not already present)
    updated_ids =
      if kill_id in kill_ids do
        kill_ids
      else
        # Keep only the most recent 100
        [kill_id | kill_ids] |> Enum.take(100)
      end

    # Update the cache
    CacheRepo.set(CacheKeys.zkill_recent_kills(), updated_ids, @kill_ttl)
  end
end
