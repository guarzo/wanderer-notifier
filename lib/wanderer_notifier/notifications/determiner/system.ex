defmodule WandererNotifier.Notifications.Determiner.System do
  @moduledoc """
  Determines whether system notifications should be sent.
  Handles all system-related notification decision logic.
  """

  require Logger
  alias WandererNotifier.Config.Features
  alias WandererNotifier.Data.Cache.Keys, as: CacheKeys
  alias WandererNotifier.Data.Cache.Repository, as: CacheRepo
  alias WandererNotifier.Helpers.DeduplicationHelper
  alias WandererNotifier.Logger.Logger, as: AppLogger

  @doc """
  Determines if a notification should be sent for a system.

  ## Parameters
    - system_id: The ID of the system to check
    - system_data: The system data to check

  ## Returns
    - true if a notification should be sent
    - false otherwise
  """
  def should_notify?(system_id, system_data) when is_map(system_data) do
    with true <- Features.system_notifications_enabled?(),
         true <- tracked_system?(system_id),
         true <- system_changed?(system_id, system_data) do
      check_deduplication_and_decide(system_id)
    else
      false -> false
      _ -> false
    end
  end

  def should_notify?(_, _), do: false

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
    AppLogger.processor_debug("[Determiner] Checking if system #{system_id_str} is tracked")

    # First check if we have a direct tracking entry for the system
    cache_key = CacheKeys.tracked_system(system_id_str)
    cache_value = CacheRepo.get(cache_key)

    # Log the cache check
    AppLogger.processor_debug("[Determiner] Tracked system cache check",
      system_id: system_id_str,
      value: inspect(cache_value)
    )

    # Get the system details from cache too
    system_cache_key = CacheKeys.system(system_id_str)
    system_in_cache = CacheRepo.get(system_cache_key)

    AppLogger.processor_debug("[Determiner] System cache check",
      system_id: system_id_str,
      system: inspect(system_in_cache)
    )

    # Return tracking status with detailed logging
    tracked = cache_value != nil

    AppLogger.processor_debug("[Determiner] System tracking check result",
      system_id: system_id_str,
      tracked: tracked,
      system_cache_key: system_cache_key,
      system_in_cache: system_in_cache != nil
    )

    tracked
  end

  def tracked_system?(_), do: false

  @doc """
  Checks if a system's data has changed from what's in cache.

  ## Parameters
    - system_id: The ID of the system to check
    - system_data: The new system data to compare against cache

  ## Returns
    - true if the system data has changed
    - false otherwise
  """
  def system_changed?(system_id, system_data) when is_map(system_data) do
    # Get cached system data
    cache_key = CacheKeys.system(system_id)
    cached_data = CacheRepo.get(cache_key)

    # Compare relevant fields
    case cached_data do
      nil ->
        # No cached data, consider it changed
        true

      cached when is_map(cached) ->
        # Compare relevant fields
        changed?(cached, system_data, [
          "security_status",
          "statics",
          "wormhole_class",
          "system_name",
          "constellation_name",
          "region_name"
        ])

      _ ->
        # Invalid cache data, consider it changed
        true
    end
  end

  def system_changed?(_, _), do: false

  # Check if any of the specified fields have changed
  defp changed?(old_data, new_data, fields) do
    Enum.any?(fields, fn field ->
      old_value = Map.get(old_data, field)
      new_value = Map.get(new_data, field)
      old_value != new_value
    end)
  end

  # Apply deduplication check and decide whether to send notification
  defp check_deduplication_and_decide(system_id) do
    case DeduplicationHelper.duplicate?(:system, system_id) do
      {:ok, :new} ->
        # Not a duplicate, allow sending
        true

      {:ok, :duplicate} ->
        # Duplicate, skip notification
        false

      {:error, reason} ->
        # Error during deduplication check - default to allowing
        AppLogger.processor_warn(
          "Deduplication check failed, allowing notification by default",
          %{
            system_id: system_id,
            error: inspect(reason)
          }
        )

        true
    end
  end
end
