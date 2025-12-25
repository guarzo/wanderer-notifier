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
    payload = Map.get(event, "payload", %{})

    SharedEventLogic.handle_entity_event(
      event,
      map_slug,
      :system_added,
      &create_system_from_payload/1,
      &handle_cache_update(&1, payload),
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
    payload = Map.get(event, "payload", %{})

    SharedEventLogic.handle_entity_event(
      event,
      map_slug,
      :system_updated,
      &create_system_from_payload/1,
      &handle_cache_update(&1, payload),
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

  defp handle_cache_update(enriched_system, payload) do
    with :ok <- update_system_cache(enriched_system),
         :ok <- cache_individual_system(enriched_system, payload) do
      :ok
    else
      error -> error
    end
  end

  defp update_system_cache(system) do
    cache_key = Cache.Keys.map_systems()

    case Cache.get(cache_key) do
      {:ok, cached_systems} when is_list(cached_systems) ->
        updated_systems = update_system_in_list(cached_systems, system)
        Logger.debug("Storing system in cache, type: #{inspect(system.__struct__)}")
        Cache.put_with_ttl(cache_key, updated_systems, Cache.ttl(:map_data))

      {:ok, nil} ->
        Cache.put_with_ttl(cache_key, [system], Cache.ttl(:map_data))

      {:error, :not_found} ->
        # Cache is empty, create new entry
        Cache.put_with_ttl(cache_key, [system], Cache.ttl(:map_data))
    end
  end

  defp cache_individual_system(system, payload) do
    system_id = to_string(system.solar_system_id)

    # Store the raw payload data to preserve custom_name and other fields
    # This mirrors what MapTrackingClient does when fetching from API
    Cache.put_tracked_system(system_id, payload)

    Logger.debug("Cached individual system data",
      system_id: system_id,
      has_custom_name: Map.has_key?(payload, "custom_name"),
      custom_name: Map.get(payload, "custom_name"),
      category: :cache
    )

    :ok
  end

  defp remove_system_from_cache(payload) do
    cache_key = Cache.Keys.map_systems()

    # IMPORTANT: Use solar_system_id for cache operations, falling back to id
    # The individual cache is keyed by solar_system_id (EVE system ID like 30000142),
    # not by the map-internal "id" field (which may be a UUID or database ID).
    system_id = Map.get(payload, "solar_system_id") || Map.get(payload, "id")

    Logger.debug("Removing system from cache",
      solar_system_id: Map.get(payload, "solar_system_id"),
      id: Map.get(payload, "id"),
      resolved_system_id: system_id,
      category: :cache
    )

    # Remove from main systems list
    result =
      cache_key
      |> Cache.get()
      |> handle_cache_result_for_removal(cache_key, system_id)

    # Also remove individual system cache entry
    if system_id do
      system_id
      |> to_string()
      |> Cache.Keys.tracked_system()
      |> Cache.delete()
    end

    result
  end

  defp handle_cache_result_for_removal({:ok, cached_systems}, cache_key, system_id)
       when is_list(cached_systems) do
    updated_systems = filter_out_system(cached_systems, system_id)
    Cache.put_with_ttl(cache_key, updated_systems, Cache.ttl(:map_data))
  end

  defp handle_cache_result_for_removal({:ok, nil}, _cache_key, _system_id) do
    # No cached systems, nothing to remove
    :ok
  end

  defp handle_cache_result_for_removal({:error, :not_found}, _cache_key, _system_id) do
    # No cached systems, nothing to remove
    :ok
  end

  defp filter_out_system(systems, system_id) do
    Enum.reject(systems, &has_matching_system_id?(&1, system_id))
  end

  defp has_matching_system_id?(%System{solar_system_id: sid}, system_id) do
    compare_system_ids(sid, system_id)
  end

  defp has_matching_system_id?(%{solar_system_id: sid}, system_id) do
    compare_system_ids(sid, system_id)
  end

  defp has_matching_system_id?(%{"solar_system_id" => sid}, system_id) do
    compare_system_ids(sid, system_id)
  end

  defp has_matching_system_id?(%{id: id}, system_id) do
    compare_system_ids(id, system_id)
  end

  defp has_matching_system_id?(%{"id" => id}, system_id) do
    compare_system_ids(id, system_id)
  end

  defp has_matching_system_id?(_, _), do: false

  # Helper to compare system IDs regardless of type (string vs integer)
  defp compare_system_ids(id1, id2) do
    normalize_id(id1) == normalize_id(id2)
  end

  defp normalize_id(id) when is_integer(id), do: id

  defp normalize_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {int_id, ""} -> int_id
      _ -> id
    end
  end

  defp normalize_id(id), do: id

  defp update_system_in_list(systems, new_system) do
    system_id = new_system.solar_system_id

    case find_system_index(systems, system_id) do
      nil ->
        # System not found, add it
        [new_system | systems]

      index ->
        # System found, update it
        List.replace_at(systems, index, new_system)
    end
  end

  defp find_system_index(systems, system_id) do
    Enum.find_index(systems, &system_matches?(&1, system_id))
  end

  defp system_matches?(%System{solar_system_id: sid}, system_id), do: sid == system_id
  defp system_matches?(%{solar_system_id: sid}, system_id), do: sid == system_id
  defp system_matches?(_, _), do: false

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
    Logger.debug("send_system_notification called with type: #{inspect(system.__struct__)}")
    Logger.debug("System keys: #{inspect(Map.keys(system))}")

    # Send system notification directly - always returns :ok immediately
    WandererNotifier.DiscordNotifier.send_system_async(system)

    Logger.debug("System notification queued",
      system_name: system.name,
      category: :api
    )

    :ok
  end
end
