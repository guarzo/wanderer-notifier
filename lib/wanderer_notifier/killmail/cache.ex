defmodule WandererNotifier.Killmail.Cache do
  @moduledoc """
  Manages caching for killmail data.

  - Stores recent kills in the cache repository
  - Provides retrieval methods for cached kills
  - Maintains a list of kill IDs for quick access
  """
  alias WandererNotifier.Cache.Keys, as: CacheKeys
  alias WandererNotifier.Cache.CachexImpl, as: CacheRepo
  alias WandererNotifier.Logger.Logger, as: AppLogger
  alias WandererNotifier.Config

  # System name cache - process dictionary for performance
  @system_names_cache_key :system_names_cache

  @doc """
  Initializes the killmail cache system.
  """
  def init do
    # Initialize the system names cache in the process dictionary
    Process.put(@system_names_cache_key, %{})
    AppLogger.kill_debug("Kill cache initialized")
    :ok
  end

  @doc """
  Caches a killmail for quick access.
  """
  def cache_kill(killmail_id, killmail) when is_binary(killmail_id) or is_integer(killmail_id) do
    kill_id = to_string(killmail_id)

    # Cache individual kill
    individual_key = CacheKeys.zkill_recent_kill(kill_id)

    AppLogger.cache_debug("Caching individual kill", key: individual_key)
    CacheRepo.set(individual_key, killmail, Config.static_info_ttl())

    # Update the recent kills list
    update_recent_kills_list(kill_id)

    :ok
  end

  @doc """
  Gets a cached killmail by ID.
  """
  def get_kill(kill_id) when is_binary(kill_id) or is_integer(kill_id) do
    id = to_string(kill_id)

    # Get the list of cached kill IDs
    kill_ids =
      case CacheRepo.get(CacheKeys.zkill_recent_kills()) do
        {:ok, ids} -> ids
        _ -> []
      end

    # Check if this kill is in our tracked list
    if id in kill_ids do
      # Get the individual kill data
      key = CacheKeys.zkill_recent_kill(id)

      kill_data =
        case CacheRepo.get(key) do
          {:ok, data} -> data
          _ -> nil
        end

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
  """
  def get_recent_kills do
    with {:ok, kill_ids} <- get_cached_kill_ids(),
         {:ok, kills} <- fetch_kills_by_ids(kill_ids) do
      {:ok, kills}
    else
      _ -> {:ok, %{}}
    end
  end

  defp get_cached_kill_ids do
    case CacheRepo.get(CacheKeys.zkill_recent_kills()) do
      {:ok, ids} -> {:ok, ids}
      _ -> {:ok, []}
    end
  end

  defp fetch_kills_by_ids(kill_ids) do
    keys = Enum.map(kill_ids, &CacheKeys.zkill_recent_kill/1)

    case CacheRepo.mget(keys) do
      {:ok, results} ->
        kills = process_kill_results(kill_ids, results)
        {:ok, kills}

      _ ->
        {:ok, %{}}
    end
  end

  defp process_kill_results(kill_ids, results) do
    kill_ids
    |> Enum.zip(results)
    |> Enum.filter(&valid_kill_result?/1)
    |> Enum.map(&extract_kill_data/1)
    |> Enum.into(%{})
  end

  defp valid_kill_result?({_id, {:ok, data}}) when not is_nil(data), do: true
  defp valid_kill_result?(_), do: false

  defp extract_kill_data({id, {:ok, data}}), do: {id, data}

  @doc """
  Gets all recent cached kills as a list for API consumption.

  ## Returns
  - List of killmails with their IDs
  """
  def get_latest_killmails do
    # Get the list of cached kill IDs
    kill_ids =
      case CacheRepo.get(CacheKeys.zkill_recent_kills()) do
        {:ok, ids} -> ids
        _ -> []
      end

    # Map through and get each kill
    kill_ids
    |> Enum.map(fn id ->
      key = CacheKeys.zkill_recent_kill(id)

      kill =
        case CacheRepo.get(key) do
          {:ok, data} -> data
          _ -> nil
        end

      if kill do
        Map.put(kill, "id", id)
      else
        nil
      end
    end)
    |> Enum.reject(&is_nil/1)
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

  # Helper to update the recent kills list with a new kill ID
  defp update_recent_kills_list(kill_id) do
    # Get current list of kill IDs
    kill_ids =
      case CacheRepo.get(CacheKeys.zkill_recent_kills()) do
        {:ok, ids} -> ids
        _ -> []
      end

    # Add the new kill ID to the list (if not already present)
    updated_ids =
      if kill_id in kill_ids do
        kill_ids
      else
        # Keep only the most recent 100
        [kill_id | kill_ids] |> Enum.take(100)
      end

    # Update the cache
    CacheRepo.set(CacheKeys.zkill_recent_kills(), updated_ids, Config.static_info_ttl())
  end
end
