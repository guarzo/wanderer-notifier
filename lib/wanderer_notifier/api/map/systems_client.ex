defmodule WandererNotifier.Api.Map.SystemsClient do
  @moduledoc """
  Client for retrieving and processing system data from the map API.
  Uses structured data types and consistent parsing to simplify the logic.
  """
  require Logger
  alias WandererNotifier.Logger, as: AppLogger
  alias WandererNotifier.Api.Http.Client
  alias WandererNotifier.Api.Map.UrlBuilder
  alias WandererNotifier.Api.Map.SystemStaticInfo
  alias WandererNotifier.Data.Cache.Repository, as: CacheRepo
  alias WandererNotifier.Core.Config
  alias WandererNotifier.Core.Config.Timings
  alias WandererNotifier.Notifiers.Factory, as: NotifierFactory
  alias WandererNotifier.Data.MapSystem

  @doc """
  Updates the system information in the cache.

  If cached_systems is provided, it will also identify and notify about new systems.

  ## Parameters
    - cached_systems: Optional list of cached systems for comparison

  ## Returns
    - {:ok, systems} on success
    - {:error, reason} on failure
  """
  def update_systems(cached_systems \\ nil) do
    AppLogger.api_debug("[SystemsClient] Starting systems update")

    case UrlBuilder.build_url("map/systems") do
      {:ok, url} ->
        headers = UrlBuilder.get_auth_headers()
        process_systems_request(url, headers, cached_systems)

      {:error, reason} ->
        AppLogger.api_error("[SystemsClient] Failed to build URL or headers: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp process_systems_request(url, headers, cached_systems) do
    case Client.get(url, headers) do
      {:ok, response} ->
        process_systems_response(response, cached_systems)

      {:error, reason} ->
        AppLogger.api_error("[SystemsClient] HTTP request failed: #{inspect(reason)}")
        {:error, {:http_error, reason}}
    end
  end

  defp process_systems_response(response, cached_systems) do
    alias WandererNotifier.Api.Http.ErrorHandler

    case ErrorHandler.handle_http_response(response, domain: :map, tag: "SystemsClient") do
      {:ok, parsed_response} ->
        process_systems_data(parsed_response, cached_systems)

      {:error, reason} ->
        AppLogger.api_error("[SystemsClient] Failed to process API response: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp process_systems_data(parsed_response, cached_systems) do
    # Extract systems data with fallbacks for different API formats
    systems_data =
      case parsed_response do
        %{"data" => data} when is_list(data) -> data
        %{"systems" => systems} when is_list(systems) -> systems
        data when is_list(data) -> data
        _ -> []
      end

    # Convert to MapSystem structs
    AppLogger.api_debug(
      "[SystemsClient] Parsing #{length(systems_data)} systems from API response"
    )

    # Transform each system into a MapSystem struct
    systems = Enum.map(systems_data, &create_map_system/1)

    # Filter systems based on configuration
    track_all_systems = WandererNotifier.Core.Config.track_kspace_systems?()

    tracked_systems =
      if track_all_systems do
        systems
      else
        # Only track wormhole systems if K-Space tracking is disabled
        Enum.filter(systems, &MapSystem.wormhole?/1)
      end

    # Log status
    wormhole_count = Enum.count(systems, &MapSystem.wormhole?/1)

    AppLogger.api_info(
      "[SystemsClient] Tracking #{length(tracked_systems)} systems (#{wormhole_count} wormholes) " <>
        "out of #{length(systems)} total systems (tracking K-Space=#{track_all_systems})"
    )

    # Cache systems and notify about new ones
    cache_systems_data(tracked_systems)
    _ = notify_new_systems(tracked_systems, cached_systems)

    {:ok, tracked_systems}
  end

  defp create_map_system(system_data) do
    # Create the base MapSystem struct
    map_system = MapSystem.new(system_data)

    # Enrich with static info if it's a wormhole system
    if MapSystem.wormhole?(map_system) do
      enrich_wormhole_system(map_system)
    else
      map_system
    end
  end

  defp enrich_wormhole_system(map_system) do
    case SystemStaticInfo.enrich_system(map_system) do
      {:ok, enriched_system} ->
        AppLogger.api_debug("[SystemsClient] Successfully enriched system #{map_system.name}")
        enriched_system

      {:error, _reason} ->
        # If enrichment fails, still use the base MapSystem
        map_system
    end
  end

  defp cache_systems_data(wormhole_systems) do
    # Cache the systems in a way that maintains the MapSystem structs
    CacheRepo.set("map:systems", wormhole_systems, Timings.systems_cache_ttl())

    # Cache just the system IDs for faster lookups
    system_ids = Enum.map(wormhole_systems, & &1.solar_system_id)
    CacheRepo.set("map:system_ids", system_ids, Timings.systems_cache_ttl())
  end

  @doc """
  Identifies new systems by comparing with cached systems and sends notifications.

  ## Parameters
    - fresh_systems: List of newly fetched systems
    - cached_systems: List of previously cached systems

  ## Returns
    - {:ok, added_systems} with list of newly added systems
  """
  def notify_new_systems(fresh_systems, cached_systems) do
    if Config.system_notifications_enabled?() do
      process_system_notifications(fresh_systems, cached_systems)
    else
      AppLogger.api_info("[SystemsClient] System notifications are disabled, skipping")
      {:ok, []}
    end
  end

  defp process_system_notifications(fresh_systems, cached_systems) do
    # Ensure we have both fresh and cached systems as lists
    fresh = fresh_systems || []
    cached = cached_systems || []

    # Find new systems and send notifications
    added_systems = find_new_systems(fresh, cached)
    log_added_systems(added_systems)

    # Send notifications for each new system
    Enum.each(added_systems, &send_system_notification/1)

    {:ok, added_systems}
  end

  defp find_new_systems(_fresh, []) do
    # If there's no cached systems, this is probably the first run
    # Don't notify about all systems to avoid spamming
    Logger.info(
      "[SystemsClient] No cached systems found; skipping new system notifications on startup"
    )

    []
  end

  defp find_new_systems(fresh, cached) do
    # Handle both struct and map types in cached systems
    Enum.filter(fresh, fn fresh_sys ->
      not system_exists_in_cache?(fresh_sys, cached)
    end)
  end

  defp system_exists_in_cache?(fresh_sys, cached) do
    fresh_id = extract_system_id(fresh_sys)

    Enum.any?(cached, fn cached_sys ->
      cached_id = extract_system_id(cached_sys)
      fresh_id == cached_id
    end)
  end

  defp extract_system_id(system) do
    if is_struct(system), do: system.id, else: system["id"]
  end

  defp log_added_systems([]), do: :ok

  defp log_added_systems(added_systems) do
    AppLogger.api_info(
      "[SystemsClient] Found #{length(added_systems)} new systems to notify about"
    )
  end

  defp send_system_notification(system) do
    Task.start(fn ->
      try do
        map_system = ensure_map_system(system)
        log_system_details(map_system)
        send_notification(map_system)
      rescue
        e ->
          Logger.error(
            "[SystemsClient] Error sending system notification: #{inspect(e)}\n#{Exception.format_stacktrace()}"
          )
      end
    end)
  end

  defp ensure_map_system(system) do
    if is_struct(system, MapSystem), do: system, else: MapSystem.new(system)
  end

  defp log_system_details(map_system) do
    if MapSystem.wormhole?(map_system) do
      log_wormhole_system_details(map_system)
    else
      log_non_wormhole_system_details(map_system)
    end
  end

  defp log_wormhole_system_details(map_system) do
    statics_list = map_system.statics || []
    type_description = map_system.type_description || "Unknown"
    class_title = map_system.class_title

    Logger.info(
      "[SystemsClient] Processing wormhole system notification - " <>
        "ID: #{map_system.solar_system_id}, " <>
        "Name: #{map_system.name}, " <>
        "Type: #{type_description}, " <>
        "Class: #{class_title}, " <>
        "Statics: #{Enum.join(statics_list, ", ")}"
    )
  end

  defp log_non_wormhole_system_details(map_system) do
    Logger.info(
      "[SystemsClient] Processing non-wormhole system notification - " <>
        "ID: #{map_system.solar_system_id}, " <>
        "Name: #{map_system.name}, " <>
        "Type: #{map_system.type_description}"
    )
  end

  defp send_notification(map_system) do
    notifier = NotifierFactory.get_notifier()
    notifier.send_new_system_notification(map_system)
  end
end
