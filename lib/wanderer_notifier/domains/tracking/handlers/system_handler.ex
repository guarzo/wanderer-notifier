defmodule WandererNotifier.Domains.Tracking.Handlers.SystemHandler do
  @moduledoc """
  Handles system-related events from the SSE stream using unified tracking infrastructure.

  This module processes system events (add, delete, metadata changes) and integrates
  with the existing notification pipeline while using shared event handling patterns.
  """

  require Logger
  alias WandererNotifier.Domains.Tracking.Entities.System
  alias WandererNotifier.Domains.Notifications.Determiner
  alias WandererNotifier.Infrastructure.Cache
  alias WandererNotifier.Domains.Tracking.Handlers.SharedEventLogic

  @behaviour WandererNotifier.Domains.Tracking.Handlers.EventHandlerBehaviour

  # ══════════════════════════════════════════════════════════════════════════════
  # Event Handler Implementation
  # ══════════════════════════════════════════════════════════════════════════════

  @impl true
  @spec handle_entity_added(map(), String.t()) :: :ok | {:error, term()}
  def handle_entity_added(event, map_slug) do
    SharedEventLogic.handle_entity_event(
      event,
      map_slug,
      :system_added,
      &create_system_from_payload/1,
      &handle_cache_update/1,
      &maybe_send_notification/1
    )
  end

  @impl true
  @spec handle_entity_removed(map(), String.t()) :: :ok | {:error, term()}
  def handle_entity_removed(event, map_slug) do
    SharedEventLogic.handle_entity_event(
      event,
      map_slug,
      :system_removed,
      &extract_system_payload/1,
      &remove_system_from_cache/1,
      &maybe_log_system_removal/1
    )
  end

  @impl true
  @spec handle_entity_updated(map(), String.t()) :: :ok | {:error, term()}
  def handle_entity_updated(event, map_slug) do
    SharedEventLogic.handle_entity_event(
      event,
      map_slug,
      :system_updated,
      &create_system_from_payload/1,
      &update_system_cache/1,
      &maybe_log_system_update/1
    )
  end

  # ══════════════════════════════════════════════════════════════════════════════
  # System-Specific Implementation (Legacy API Compatibility)
  # ══════════════════════════════════════════════════════════════════════════════

  # ══════════════════════════════════════════════════════════════════════════════
  # System-Specific Data Processing
  # ══════════════════════════════════════════════════════════════════════════════

  defp create_system_from_payload(payload) do
    with {:ok, system} <- try_create_system(payload),
         {:ok, enriched_system} <- enrich_system(system) do
      {:ok, enriched_system}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp try_create_system(payload) do
    try do
      # Log the incoming payload to see what we're getting
      Logger.debug("Creating system from SSE payload",
        payload: inspect(payload),
        category: :api
      )

      system = System.from_api_data(payload)
      {:ok, system}
    rescue
      error ->
        Logger.error("Failed to create system from payload",
          payload: inspect(payload),
          category: :api,
          error: inspect(error)
        )

        {:error, {:system_creation_failed, error}}
    end
  end

  defp enrich_system(system) do
    try do
      Logger.debug("Enriching system",
        system_id: system.solar_system_id,
        system_name: system.name,
        before_enrichment: inspect(system),
        category: :api
      )

      # StaticInfo.enrich_system returns {:ok, enriched_system}
      # enrich_system always returns {:ok, system}
      {:ok, enriched} = WandererNotifier.Domains.Tracking.StaticInfo.enrich_system(system)

      Logger.debug("System enriched successfully",
        system_id: enriched.solar_system_id,
        system_name: enriched.name,
        class_title: enriched.class_title,
        statics: inspect(enriched.statics),
        region: enriched.region_name,
        category: :api
      )

      {:ok, enriched}
    rescue
      error ->
        Logger.error("Failed to enrich system",
          system: inspect(system),
          category: :api,
          error: inspect(error)
        )

        {:error, {:enrichment_failed, error}}
    end
  end

  defp extract_system_payload(payload) do
    # For removal events, we just need the payload as-is
    {:ok, payload}
  end

  # ══════════════════════════════════════════════════════════════════════════════
  # System-Specific Cache Operations
  # ══════════════════════════════════════════════════════════════════════════════

  defp handle_cache_update(enriched_system) do
    update_system_cache(enriched_system)
  end

  defp update_system_cache(system) do
    cache_key = Cache.Keys.map_systems()

    case Cache.get(cache_key) do
      {:ok, cached_systems} when is_list(cached_systems) ->
        updated_systems = update_system_in_list(cached_systems, system)
        Cache.put_with_ttl(cache_key, updated_systems, Cache.map_ttl())

      {:ok, nil} ->
        Cache.put_with_ttl(cache_key, [system], Cache.map_ttl())

      {:error, reason} ->
        Logger.error("Failed to read system cache",
          cache_key: cache_key,
          error: inspect(reason),
          category: :api
        )

        {:error, {:cache_read_failed, reason}}
    end
  end

  defp remove_system_from_cache(payload) do
    cache_key = Cache.Keys.map_systems()

    case Cache.get(cache_key) do
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

        Cache.put_with_ttl(cache_key, updated_systems, Cache.map_ttl())

      {:ok, nil} ->
        # No cached systems, nothing to remove
        :ok

      {:error, reason} ->
        Logger.error("Failed to read system cache for removal",
          cache_key: cache_key,
          error: inspect(reason),
          category: :api
        )

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

  # ══════════════════════════════════════════════════════════════════════════════
  # System-Specific Notification Logic
  # ══════════════════════════════════════════════════════════════════════════════

  defp maybe_send_notification(system) do
    # Use the existing system determiner to check if we should notify
    # Pass the system_id as first parameter, and the system struct as second
    case Determiner.should_notify?(:system, system.solar_system_id, system) do
      true ->
        send_system_notification(system)

      false ->
        Logger.info("System notification skipped",
          system_name: system.name,
          reason: "determiner_rejected",
          category: :api
        )

        :ok
    end
  end

  defp maybe_log_system_removal(payload) do
    Logger.debug("System removed from tracking",
      system_id: Map.get(payload, "id"),
      category: :api
    )

    :ok
  end

  defp maybe_log_system_update(system) do
    Logger.debug("System metadata updated",
      system_name: system.name,
      category: :api
    )

    :ok
  end

  defp send_system_notification(system) do
    case WandererNotifier.Contexts.NotificationContext.send_system_notification(system) do
      {:ok, :skipped} ->
        Logger.debug("System notification skipped",
          system_name: system.name,
          category: :api
        )

        :ok

      {:ok, _} ->
        Logger.debug("System notification sent",
          system_name: system.name,
          system_id: system.solar_system_id,
          category: :api
        )

        :ok

      {:error, reason} ->
        Logger.error("Failed to send system notification",
          system_name: system.name,
          error: inspect(reason),
          category: :api
        )

        {:error, {:notification_failed, reason}}
    end
  end
end
