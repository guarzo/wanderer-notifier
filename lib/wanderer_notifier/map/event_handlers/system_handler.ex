defmodule WandererNotifier.Map.EventHandlers.SystemHandler do
  @moduledoc """
  Handles system-related events from the SSE stream.

  This module processes system events (add, delete, metadata changes)
  and integrates with the existing notification pipeline.
  """

  require Logger
  alias WandererNotifier.Logger.Logger, as: AppLogger
  alias WandererNotifier.Map.MapSystem
  alias WandererNotifier.Map.SystemStaticInfo
  alias WandererNotifier.Notifications.Determiner.System, as: SystemDeterminer
  alias WandererNotifier.Notifiers.Discord.Notifier, as: DiscordNotifier
  alias WandererNotifier.Cache.Keys, as: CacheKeys

  @doc """
  Handles the `add_system` event.

  This event is fired when a new system is added to the map.
  We process it similarly to how we handle new systems in the polling approach,
  but without the need for cache comparison.
  """
  @spec handle_system_added(map(), String.t()) :: :ok | {:error, term()}
  def handle_system_added(event, map_slug) do
    payload = Map.get(event, "payload")

    AppLogger.api_info("Processing add_system event",
      map_slug: map_slug,
      system_data: inspect(payload)
    )

    with {:ok, system} <- create_system_from_payload(payload),
         {:ok, enriched_system} <- enrich_system(system),
         :ok <- handle_cache_update(enriched_system, map_slug) do
      maybe_send_notification(enriched_system, map_slug)
    else
      {:error, {:system_creation_failed, error, failed_payload}} ->
        log_system_creation_error(map_slug, error, failed_payload)
        {:error, {:system_creation_failed, error}}

      {:error, reason} = error ->
        AppLogger.api_error("Failed to process add_system event",
          map_slug: map_slug,
          error: inspect(reason)
        )

        error
    end
  end

  @doc """
  Handles the `deleted_system` event.

  This event is fired when a system is removed from the map.
  We update our cache but don't send notifications for deletions.
  """
  @spec handle_system_deleted(map(), String.t()) :: :ok | {:error, term()}
  def handle_system_deleted(event, map_slug) do
    payload = Map.get(event, "payload")

    AppLogger.api_info("Processing deleted_system event",
      map_slug: map_slug,
      system_data: inspect(payload)
    )

    case remove_system_from_cache(payload) do
      :ok ->
        AppLogger.api_info("System removed from cache",
          map_slug: map_slug,
          system_id: Map.get(payload, "id")
        )

        :ok

      {:error, reason} = error ->
        AppLogger.api_error("Failed to process deleted_system event",
          map_slug: map_slug,
          error: inspect(reason)
        )

        error
    end
  end

  @doc """
  Handles the `system_metadata_changed` event.

  This event is fired when system properties are updated.
  We update our cache but typically don't send notifications for metadata changes.
  """
  @spec handle_system_metadata_changed(map(), String.t()) :: :ok | {:error, term()}
  def handle_system_metadata_changed(event, map_slug) do
    payload = Map.get(event, "payload")

    AppLogger.api_info("Processing system_metadata_changed event",
      map_slug: map_slug,
      system_data: inspect(payload)
    )

    with {:ok, system} <- create_system_from_payload(payload),
         {:ok, enriched_system} <- enrich_system(system),
         :ok <- update_system_cache(enriched_system) do
      AppLogger.api_info("System metadata updated",
        map_slug: map_slug,
        system_name: enriched_system.name
      )

      :ok
    else
      {:error, {:system_creation_failed, error, failed_payload}} ->
        log_system_creation_error(map_slug, error, failed_payload)
        {:error, {:system_creation_failed, error}}

      {:error, reason} = error ->
        AppLogger.api_error("Failed to process system_metadata_changed event",
          map_slug: map_slug,
          error: inspect(reason)
        )

        error
    end
  end

  # Private helper functions

  defp log_system_creation_error(map_slug, error, payload) do
    AppLogger.api_error("Failed to create system from payload",
      map_slug: map_slug,
      payload: inspect(payload),
      error: inspect(error)
    )
  end

  defp handle_cache_update(enriched_system, map_slug) do
    case update_system_cache(enriched_system) do
      :ok ->
        :ok

      {:error, reason} = error ->
        AppLogger.api_error("Failed to update system cache",
          map_slug: map_slug,
          error: inspect(reason)
        )

        error
    end
  end

  defp create_system_from_payload(payload) do
    try do
      system = MapSystem.new(payload)
      {:ok, system}
    rescue
      error ->
        {:error, {:system_creation_failed, error, payload}}
    end
  end

  defp enrich_system(system) do
    try do
      # SystemStaticInfo.enrich_system returns {:ok, enriched_system}
      SystemStaticInfo.enrich_system(system)
    rescue
      error ->
        AppLogger.api_error("Failed to enrich system",
          system: inspect(system),
          error: inspect(error)
        )

        {:error, {:enrichment_failed, error}}
    end
  end

  defp update_system_cache(system) do
    cache_name = Application.get_env(:wanderer_notifier, :cache_name, :wanderer_cache)
    cache_key = CacheKeys.map_systems()

    cache_name
    |> Cachex.get(cache_key)
    |> handle_cache_result(cache_name, cache_key, system)
  end

  defp handle_cache_result({:ok, cached_systems}, cache_name, cache_key, system)
       when is_list(cached_systems) do
    updated_systems = update_system_in_list(cached_systems, system)
    put_cache(cache_name, cache_key, updated_systems, :cache_update_failed)
  end

  defp handle_cache_result({:ok, nil}, cache_name, cache_key, system) do
    put_cache(cache_name, cache_key, [system], :cache_creation_failed)
  end

  defp handle_cache_result({:error, reason}, _, _, _) do
    {:error, {:cache_read_failed, reason}}
  end

  defp put_cache(cache_name, cache_key, data, error_type) do
    case Cachex.put(cache_name, cache_key, data) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, {error_type, reason}}
    end
  end

  defp remove_system_from_cache(payload) do
    cache_name = Application.get_env(:wanderer_notifier, :cache_name, :wanderer_cache)
    cache_key = CacheKeys.map_systems()

    case Cachex.get(cache_name, cache_key) do
      {:ok, cached_systems} when is_list(cached_systems) ->
        # Remove the system from the cache
        system_id = Map.get(payload, "id")

        updated_systems =
          Enum.reject(cached_systems, fn system ->
            # Handle both potential ID fields in cached systems
            Map.get(system, :solar_system_id) == system_id || 
            Map.get(system, :id) == system_id ||
            Map.get(system, "id") == system_id
          end)

        case Cachex.put(cache_name, cache_key, updated_systems) do
          {:ok, _} ->
            :ok

          {:error, reason} ->
            {:error, {:cache_update_failed, reason}}
        end

      {:ok, nil} ->
        # No cached systems, nothing to remove
        :ok

      {:error, reason} ->
        {:error, {:cache_read_failed, reason}}
    end
  end

  defp update_system_in_list(systems, new_system) do
    system_id = new_system.solar_system_id

    case Enum.find_index(systems, fn system ->
           Map.get(system, :solar_system_id) == system_id
         end) do
      nil ->
        # System not found, add it
        [new_system | systems]

      index ->
        # System found, update it
        List.replace_at(systems, index, new_system)
    end
  end

  defp maybe_send_notification(system, map_slug) do
    # Use the existing system determiner to check if we should notify
    # Pass the system_id as first parameter, and the system struct as second
    case SystemDeterminer.should_notify?(system.solar_system_id, system) do
      true ->
        send_system_notification(system, map_slug)

      false ->
        AppLogger.api_info("System notification skipped",
          map_slug: map_slug,
          system_name: system.name,
          reason: "determiner_rejected"
        )

        :ok
    end
  end

  defp send_system_notification(system, map_slug) do
    case DiscordNotifier.send_new_system_notification(system) do
      {:ok, :sent} ->
        AppLogger.api_info("System notification sent",
          map_slug: map_slug,
          system_name: system.name
        )

        :ok

      {:error, reason} ->
        AppLogger.api_error("Failed to send system notification",
          map_slug: map_slug,
          system_name: system.name,
          error: inspect(reason)
        )

        {:error, {:notification_failed, reason}}
    end
  end
end
