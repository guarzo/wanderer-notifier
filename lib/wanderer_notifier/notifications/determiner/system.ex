defmodule WandererNotifier.Notifications.Determiner.System do
  @moduledoc """
  Determines whether system notifications should be sent.
  Handles all system-related notification decision logic.
  """

  require Logger
  alias WandererNotifier.Config
  alias WandererNotifier.Cache.Keys, as: CacheKeys
  alias WandererNotifier.Cache.CachexImpl, as: CacheRepo
  alias WandererNotifier.Notifications.Helpers.Deduplication

  @doc """
  Determines if a notification should be sent for a system.

  ## Parameters
    - system_id: The ID of the system to check
    - system_data: The system data to check

  ## Returns
    - true if a notification should be sent
    - false otherwise
  """
  def should_notify?(system_id, _system_data) do
    if Config.system_notifications_enabled?() do
      case Deduplication.check(:system, system_id) do
        {:ok, :new} -> true
        {:ok, :duplicate} -> false
        {:error, _reason} -> true
      end
    else
      false
    end
  end

  @doc """
  Checks if a system's data has changed from what's in cache.

  ## Parameters
    - system_id: The ID of the system to check
    - system_data: The new system data to compare against cache

  ## Returns
    - true if the system is new (not in cache)
    - false otherwise
  """
  def system_changed?(system_id, _system_data) do
    cache_key = CacheKeys.system(system_id)

    case CacheRepo.get(cache_key) do
      # Already exists, not new
      {:ok, _cached} -> false
      # Not in cache, so it's new
      _ -> true
    end
  end

  @doc """
  Checks if a system is being tracked.

  ## Parameters
    - system_id: The ID of the system to check

  ## Returns
    - true if the system is tracked
    - false otherwise
  """
  def tracked_system?(system_id) when is_integer(system_id) do
    system_id_str = Integer.to_string(system_id)
    tracked_system?(system_id_str)
  end

  def tracked_system?(system_id_str) when is_binary(system_id_str) do
    # Get the current list of tracked systems from the cache
    case CacheRepo.get(CacheKeys.map_systems()) do
      {:ok, systems} when is_list(systems) ->
        Enum.any?(systems, fn system ->
          id = Map.get(system, :solar_system_id) || Map.get(system, "solar_system_id")
          to_string(id) == system_id_str
        end)

      _ ->
        false
    end
  end

  def tracked_system?(_), do: false

  def tracked_system_info(system_id) do
    system_cache_key = CacheKeys.system(system_id)

    case CacheRepo.get(system_cache_key) do
      {:ok, value} -> %{system_in_cache: true, value: value}
      _ -> %{system_in_cache: false, value: nil}
    end
  end
end
