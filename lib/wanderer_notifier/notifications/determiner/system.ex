defmodule WandererNotifier.Notifications.Determiner.System do
  @moduledoc """
  Determines whether system notifications should be sent.
  Handles all system-related notification decision logic.
  """

  require Logger
  alias Cachex
  alias WandererNotifier.Config
  alias WandererNotifier.Cache.Keys, as: CacheKeys
  alias WandererNotifier.Notifications.Deduplication
  alias WandererNotifier.Map.MapSystem

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
  def system_changed?(system_id, new_data) do
    cache_name = Application.get_env(:wanderer_notifier, :cache_name, :wanderer_cache)
    cache_key = CacheKeys.system(system_id)

    case Cachex.get(cache_name, cache_key) do
      {:ok, old_data} when old_data != nil ->
        old_data != new_data

      _ ->
        true
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
    MapSystem.is_tracked?(system_id_str)
  end

  def tracked_system?(_), do: false

  def tracked_system_info(system_id) do
    cache_name = Application.get_env(:wanderer_notifier, :cache_name, :wanderer_cache)
    system_cache_key = CacheKeys.system(system_id)

    case Cachex.get(cache_name, system_cache_key) do
      {:ok, info} -> info
      _ -> nil
    end
  end
end
