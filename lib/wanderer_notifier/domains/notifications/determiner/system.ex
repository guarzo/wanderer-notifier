defmodule WandererNotifier.Domains.Notifications.Determiner.System do
  @moduledoc """
  Determines whether system notifications should be sent.
  Handles all system-related notification decision logic.
  """

  require Logger
  alias WandererNotifier.Shared.Config
  alias WandererNotifier.Infrastructure.Cache
  alias WandererNotifier.Domains.Notifications.Deduplication
  alias WandererNotifier.Domains.SystemTracking.System

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
    case Cache.get_system(system_id) do
      {:ok, old_data} when old_data != nil ->
        old_data != new_data

      {:error, :not_found} ->
        true

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
    case System.is_tracked?(system_id_str) do
      {:ok, result} -> result
      {:error, _} -> false
    end
  end

  def tracked_system?(_), do: false

  def tracked_system_info(system_id) do
    case Cache.get_system(system_id) do
      {:ok, info} -> info
      {:error, :not_found} -> nil
      _ -> nil
    end
  end
end
