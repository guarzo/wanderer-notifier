defmodule WandererNotifier.Killmail.Cache do
  @moduledoc """
  Manages caching for killmail data.

  - Stores recent kills in the cache repository
  - Provides retrieval methods for cached kills
  - Maintains a list of kill IDs for quick access
  """
  alias WandererNotifier.Cache.Keys, as: CacheKeys
  alias WandererNotifier.Cache.Config, as: CacheConfig
  alias WandererNotifier.Cache.Adapter
  alias WandererNotifier.Logger.Logger, as: AppLogger

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
    cache_name = CacheConfig.cache_name()

    # Adapter expects milliseconds
    ttl_ms =
      :killmail
      |> WandererNotifier.Cache.Config.ttl_for()
      |> :timer.seconds()

    Adapter.set(
      cache_name,
      individual_key,
      killmail,
      ttl_ms
    )

    # Update the recent kills list
    update_recent_kills_list(kill_id)

    :ok
  end

  @doc """
  Gets a cached killmail by ID.
  """
  def get_kill(kill_id) when is_binary(kill_id) or is_integer(kill_id) do
    id = to_string(kill_id)
    cache_name = CacheConfig.cache_name()

    with {:ok, kill_ids} <- Adapter.get(cache_name, CacheKeys.zkill_recent_kills()),
         true <- is_list(kill_ids),
         true <- id in kill_ids,
         {:ok, data} <- Adapter.get(cache_name, CacheKeys.zkill_recent_kill(id)),
         true <- not is_nil(data) do
      {:ok, data}
    else
      _ -> {:error, :not_cached}
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
    cache_name = CacheConfig.cache_name()

    case Adapter.get(cache_name, CacheKeys.zkill_recent_kills()) do
      {:ok, ids} when is_list(ids) -> {:ok, ids}
      {:ok, nil} -> {:ok, []}
      _ -> {:ok, []}
    end
  end

  defp fetch_kills_by_ids(kill_ids) do
    cache_name = CacheConfig.cache_name()
    keys = Enum.map(kill_ids, &CacheKeys.zkill_recent_kill/1)

    results =
      Enum.map(keys, fn key ->
        case Adapter.get(cache_name, key) do
          {:ok, value} -> {:ok, value}
          _ -> {:ok, nil}
        end
      end)

    kills = process_kill_results(kill_ids, results)
    {:ok, kills}
  end

  defp process_kill_results(kill_ids, results) do
    for {id, {:ok, data}} <- Enum.zip(kill_ids, results),
        not is_nil(data),
        into: %{} do
      {id, data}
    end
  end

  @doc """
  Gets all recent cached kills as a list for API consumption.

  ## Returns
  - List of killmails with their IDs
  """
  def get_latest_killmails do
    cache_name = CacheConfig.cache_name()

    # Get the list of cached kill IDs
    kill_ids = get_cached_kill_ids(cache_name)

    # Map through and get each kill
    kill_ids
    |> Enum.map(&get_kill_by_id(cache_name, &1))
    |> Enum.reject(&is_nil/1)
  end

  defp get_cached_kill_ids(cache_name) do
    case Adapter.get(cache_name, CacheKeys.zkill_recent_kills()) do
      {:ok, ids} when is_list(ids) -> ids
      {:ok, nil} -> []
      _ -> []
    end
  end

  defp get_kill_by_id(cache_name, id) do
    case Adapter.get(cache_name, CacheKeys.zkill_recent_kill(id)) do
      {:ok, data} when not is_nil(data) -> Map.put(data, "id", id)
      _ -> nil
    end
  end

  @doc """
  Gets a system name from the cache or from the API.

  ## Parameters
  - system_id: The ID of the system to get name for

  ## Returns
  - System name string or "System [ID]" if not found
  """
  def get_system_name(nil), do: "unknown"

  def get_system_name(system_id) when is_integer(system_id) do
    case esi_service().get_system_info(system_id, []) do
      {:ok, %{"name" => name}} when is_binary(name) -> name
      _ -> "System #{system_id}"
    end
  end

  def get_system_name(system_id) when is_binary(system_id) do
    case Integer.parse(system_id) do
      {id, ""} -> get_system_name(id)
      _ -> "System #{system_id}"
    end
  end

  # Dependency injection helper
  defp esi_service,
    do: Application.get_env(:wanderer_notifier, :esi_service, WandererNotifier.ESI.Service)

  # Private functions

  # Helper to update the recent kills list with a new kill ID
  defp update_recent_kills_list(kill_id) do
    cache_name = CacheConfig.cache_name()
    # Get current list of kill IDs
    kill_ids =
      case Adapter.get(cache_name, CacheKeys.zkill_recent_kills()) do
        {:ok, ids} when is_list(ids) -> ids
        _ -> []
      end

    # Add the new kill ID to the list (if not already present)
    # Limit the list to a maximum of recent kills
    max_recent_kills = Application.get_env(:wanderer_notifier, :max_recent_kills, 100)

    updated_ids =
      if kill_id in kill_ids do
        kill_ids
      else
        [kill_id | kill_ids] |> Enum.take(max_recent_kills)
      end

    # Store the updated list
    Adapter.set(
      cache_name,
      CacheKeys.zkill_recent_kills(),
      updated_ids,
      :timer.seconds(WandererNotifier.Cache.Config.ttl_for(:killmail))
    )
  end
end
