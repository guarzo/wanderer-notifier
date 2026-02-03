defmodule WandererNotifier.Domains.Tracking.Handlers.SystemHandler do
  @moduledoc """
  Handles system-related events from the SSE stream.

  Processes system events (add, delete, metadata changes) and integrates
  with the notification pipeline.
  """

  require Logger
  alias WandererNotifier.Domains.Tracking.Entities.System
  alias WandererNotifier.Domains.Tracking.Handlers.GenericEventHandler
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
  # System-Specific Data Processing
  # ══════════════════════════════════════════════════════════════════════════════

  defp create_system_from_payload(payload) do
    with {:ok, system} <- try_create_system(payload),
         {:ok, enriched_system} <- enrich_system(system) do
      {:ok, enriched_system}
    end
  end

  defp try_create_system(payload) do
    Logger.debug("Creating system from SSE payload",
      payload: inspect(payload),
      category: :api
    )

    case System.new_safe(payload) do
      {:ok, system} ->
        {:ok, system}

      {:error, reason} ->
        Logger.error("Failed to create system from payload",
          payload: inspect(payload),
          category: :api,
          error: inspect(reason)
        )

        {:error, {:system_creation_failed, reason}}
    end
  end

  defp enrich_system(system) do
    Logger.debug("Enriching system",
      system_id: system.solar_system_id,
      system_name: system.name,
      before_enrichment: inspect(system),
      category: :api
    )

    # StaticInfo.enrich_system/1 always returns {:ok, _} - it returns the original
    # system if enrichment fails, so we don't need to handle error cases
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
  end

  defp extract_system_payload(payload) do
    {:ok, payload}
  end

  # ══════════════════════════════════════════════════════════════════════════════
  # Cache Operations (delegated to GenericEventHandler)
  # ══════════════════════════════════════════════════════════════════════════════

  # Dialyzer reports {:error, reason} clause as unreachable because current implementation
  # always returns {:ok, _}. Added for defensive programming against future changes.
  @dialyzer {:nowarn_function, handle_cache_update: 2}
  defp handle_cache_update(enriched_system, payload) do
    # Update main systems cache, then cache individual system data
    case update_system_cache(enriched_system) do
      {:ok, _result} ->
        cache_individual_system(enriched_system, payload)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp update_system_cache(system) do
    match_fn = fn cached -> system_matches?(cached, system.solar_system_id) end
    opts = [ttl: Cache.ttl(:map_data), add_if_missing: true]
    GenericEventHandler.update_in_cache_list(:system, system, match_fn, opts)
  end

  defp cache_individual_system(system, payload) do
    system_id = to_string(system.solar_system_id)
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
    system_id = Map.get(payload, "solar_system_id") || Map.get(payload, "id")

    Logger.debug("Removing system from cache",
      solar_system_id: Map.get(payload, "solar_system_id"),
      id: Map.get(payload, "id"),
      resolved_system_id: system_id,
      category: :cache
    )

    GenericEventHandler.remove_from_cache_list(:system, payload)

    # Also remove individual system cache entry
    if system_id do
      system_id
      |> to_string()
      |> Cache.Keys.tracked_system()
      |> Cache.delete()
    end

    :ok
  end

  defp system_matches?(%System{solar_system_id: sid}, system_id), do: sid == system_id
  defp system_matches?(%{solar_system_id: sid}, system_id), do: sid == system_id
  defp system_matches?(_, _), do: false

  # ══════════════════════════════════════════════════════════════════════════════
  # Notification Logic
  # ══════════════════════════════════════════════════════════════════════════════

  defp maybe_send_notification(system) do
    case GenericEventHandler.should_notify?(:system, system.solar_system_id, system) do
      {:ok, true} ->
        send_system_notification(system)
        {:ok, :sent}

      {:ok, false} ->
        Logger.info("System notification skipped",
          system_name: system.name,
          reason: "determiner_rejected",
          category: :api
        )

        {:ok, :skipped}
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

    WandererNotifier.DiscordNotifier.send_system_async(system)

    Logger.debug("System notification queued",
      system_name: system.name,
      category: :api
    )

    :ok
  end
end
