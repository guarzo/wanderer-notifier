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
  alias WandererNotifier.Domains.Tracking.StaticInfo

  alias WandererNotifier.Shared.Dependencies

  @behaviour WandererNotifier.Domains.Tracking.Handlers.EventHandlerBehaviour

  # ══════════════════════════════════════════════════════════════════════════════
  # Event Handler Implementation
  # ══════════════════════════════════════════════════════════════════════════════

  @impl true
  @spec handle_entity_added(map(), String.t()) :: :ok | {:error, term()}
  def handle_entity_added(event, map_slug) do
    payload = Map.get(event, "payload", %{})
    registry = Dependencies.map_registry()

    SharedEventLogic.handle_entity_event(
      event,
      map_slug,
      :system_added,
      &create_system_from_payload/1,
      &handle_cache_update_from_enriched(&1, payload, map_slug),
      &handle_system_added_notification(&1, map_slug, registry)
    )
  end

  @impl true
  @spec handle_entity_removed(map(), String.t()) :: :ok | {:error, term()}
  def handle_entity_removed(event, map_slug) do
    registry = Dependencies.map_registry()

    SharedEventLogic.handle_entity_event(
      event,
      map_slug,
      :system_removed,
      &extract_system_payload/1,
      &handle_system_removal(&1, map_slug, registry),
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
      &handle_cache_update_from_enriched(&1, payload, map_slug),
      &maybe_log_system_update/1
    )
  end

  # ══════════════════════════════════════════════════════════════════════════════
  # System-Specific Data Processing
  # ══════════════════════════════════════════════════════════════════════════════

  defp create_system_from_payload(payload) do
    # Fetch static info upfront — used for both name resolution and enrichment
    system_id = payload["solar_system_id"] || payload[:solar_system_id] || payload["id"]
    static_data = fetch_static_data(system_id)

    payload = maybe_resolve_system_name(payload, static_data)

    with {:ok, system} <- try_create_system(payload),
         {:ok, enriched_system} <- enrich_with_static_data(system, static_data) do
      {:ok, enriched_system}
    end
  end

  defp fetch_static_data(nil), do: nil

  defp fetch_static_data(system_id) when is_integer(system_id) and system_id > 0 do
    case StaticInfo.get_system_static_info(system_id) do
      {:ok, info} -> info
      {:error, _} -> nil
    end
  end

  defp fetch_static_data(system_id) when is_binary(system_id) do
    case Integer.parse(system_id) do
      {id, ""} when id > 0 ->
        case StaticInfo.get_system_static_info(id) do
          {:ok, info} -> info
          {:error, _} -> nil
        end

      _ ->
        nil
    end
  end

  defp fetch_static_data(_invalid), do: nil

  defp maybe_resolve_system_name(%{"name" => name} = payload, _static_data)
       when is_binary(name) and name != "",
       do: payload

  defp maybe_resolve_system_name(%{name: name} = payload, _static_data)
       when is_binary(name) and name != "",
       do: payload

  defp maybe_resolve_system_name(payload, static_data),
    do: resolve_and_inject_name(payload, static_data)

  defp resolve_and_inject_name(payload, static_data) do
    system_id = payload["solar_system_id"] || payload[:solar_system_id] || payload["id"]
    data = extract_static_data(static_data)

    case data["solar_system_name"] do
      name when is_binary(name) and name != "" ->
        Logger.info("Resolved system name from static info",
          solar_system_id: system_id,
          name: name
        )

        Map.put(payload, "name", name)

      _ ->
        Logger.warning("Could not resolve system name from static info, using fallback",
          solar_system_id: system_id
        )

        Map.put(payload, "name", "System #{system_id}")
    end
  end

  defp extract_static_data(data), do: StaticInfo.extract_data_from_static_info(data)

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

  # Dialyzer reports the non-{:ok, _} clause as unreachable because current implementation
  # always returns {:ok, _}. Added for defensive programming against future changes.
  @dialyzer {:nowarn_function, enrich_with_static_data: 2}
  defp enrich_with_static_data(system, static_data) do
    Logger.debug("Enriching system with pre-fetched static data",
      system_id: system.solar_system_id,
      system_name: system.name,
      has_static_data: not is_nil(static_data),
      category: :api
    )

    case StaticInfo.enrich_system_with_data(system, static_data) do
      {:ok, enriched} ->
        Logger.debug("System enriched successfully",
          system_id: enriched.solar_system_id,
          system_name: enriched.name,
          class_title: enriched.class_title,
          statics: inspect(enriched.statics),
          region: enriched.region_name,
          category: :api
        )

        {:ok, enriched}

      other ->
        Logger.error("Failed to enrich system with static data",
          system_id: system.solar_system_id,
          reason: inspect(other),
          category: :api
        )

        other
    end
  end

  defp extract_system_payload(payload) do
    {:ok, payload}
  end

  # ══════════════════════════════════════════════════════════════════════════════
  # Cache Operations (delegated to GenericEventHandler)
  # ══════════════════════════════════════════════════════════════════════════════

  # Dialyzer reports {:error, reason} clause as unreachable because current implementation
  # always returns {:ok, _}. Added for defensive programming against future changes.
  @dialyzer {:nowarn_function, handle_cache_update_from_enriched: 3}
  defp handle_cache_update_from_enriched(enriched_system, original_payload, map_slug) do
    # Merge enriched name into original payload so the cached data reflects the resolved name
    payload = Map.put(original_payload, "name", enriched_system.name)

    case update_system_cache(enriched_system, map_slug) do
      {:ok, _result} ->
        cache_individual_system(enriched_system, payload, map_slug)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp update_system_cache(system, map_slug) do
    match_fn = fn cached -> system_matches?(cached, system.solar_system_id) end
    opts = [ttl: Cache.ttl(:map_data), add_if_missing: true, map_slug: map_slug]
    GenericEventHandler.update_in_cache_list(:system, system, match_fn, opts)
  end

  defp cache_individual_system(system, payload, map_slug) do
    system_id = to_string(system.solar_system_id)

    case Cache.put_tracked_system(map_slug, system_id, payload) do
      :ok ->
        Logger.debug("Cached individual system data",
          system_id: system_id,
          map_slug: map_slug,
          has_custom_name: Map.has_key?(payload, "custom_name"),
          custom_name: Map.get(payload, "custom_name"),
          category: :cache
        )

        {:ok, :cached}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp handle_system_removal(payload, map_slug, registry) do
    system_id = Map.get(payload, "solar_system_id") || Map.get(payload, "id")

    Logger.debug("Removing system from cache",
      solar_system_id: Map.get(payload, "solar_system_id"),
      id: Map.get(payload, "id"),
      resolved_system_id: system_id,
      map_slug: map_slug,
      category: :cache
    )

    # GenericEventHandler.remove_from_cache_list/3 always returns {:ok, _}
    {:ok, _} = GenericEventHandler.remove_from_cache_list(:system, payload, map_slug: map_slug)

    # Also remove individual system cache entry (map-scoped)
    if system_id do
      system_id
      |> to_string()
      |> then(&Cache.Keys.tracked_system(map_slug, &1))
      |> Cache.delete()
    end

    # Update reverse index for killmail fan-out (best-effort)
    if system_id do
      try do
        case registry.deindex_system(map_slug, system_id) do
          :ok ->
            :ok

          {:ok, _} ->
            :ok

          {:error, reason} ->
            Logger.error("Failed to deindex system from reverse index",
              map_slug: map_slug,
              system_id: system_id,
              reason: inspect(reason)
            )
        end
      rescue
        e ->
          Logger.error("Failed to deindex system from reverse index",
            map_slug: map_slug,
            system_id: system_id,
            reason: Exception.message(e)
          )
      end
    end

    {:ok, :removed}
  end

  defp system_matches?(%System{solar_system_id: sid}, system_id), do: sid == system_id
  defp system_matches?(%{solar_system_id: sid}, system_id), do: sid == system_id
  defp system_matches?(_, _), do: false

  # ══════════════════════════════════════════════════════════════════════════════
  # Notification Logic
  # ══════════════════════════════════════════════════════════════════════════════

  defp handle_system_added_notification(system, map_slug, registry) do
    # Update reverse index for killmail fan-out
    try do
      registry.index_system(map_slug, system.solar_system_id)
    rescue
      error ->
        Logger.error("Failed to index system in MapRegistry",
          map_slug: map_slug,
          solar_system_id: system.solar_system_id,
          reason: Exception.message(error),
          category: :api
        )
    end

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
