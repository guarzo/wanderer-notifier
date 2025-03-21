defmodule WandererNotifier.Api.Map.SystemsClient do
  @moduledoc """
  Client for retrieving and processing system data from the map API.
  Uses structured data types and consistent parsing to simplify the logic.
  """
  require Logger
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
    Logger.debug("[SystemsClient] Starting systems update")

    with {:ok, url} <- UrlBuilder.build_url("map/systems"),
         headers = UrlBuilder.get_auth_headers() do
      # Make the API request
      case Client.get(url, headers) do
        {:ok, response} ->
          # Use the error handler to properly process the response
          alias WandererNotifier.Api.Http.ErrorHandler

          case ErrorHandler.handle_http_response(response, domain: :map, tag: "SystemsClient") do
            {:ok, parsed_response} ->
              # Extract systems data with fallbacks for different API formats
              systems_data =
                case parsed_response do
                  %{"data" => data} when is_list(data) -> data
                  %{"systems" => systems} when is_list(systems) -> systems
                  data when is_list(data) -> data
                  _ -> []
                end

              # Convert to MapSystem structs
              Logger.debug(
                "[SystemsClient] Parsing #{length(systems_data)} systems from API response"
              )

              # Transform each system into a MapSystem struct
              systems =
                Enum.map(systems_data, fn system_data ->
                  # Create the base MapSystem struct
                  map_system = MapSystem.new(system_data)

                  # Enrich with static info if it's a wormhole system
                  if MapSystem.is_wormhole?(map_system) do
                    case SystemStaticInfo.enrich_system(map_system) do
                      {:ok, enriched_system} ->
                        Logger.debug(
                          "[SystemsClient] Successfully enriched system #{map_system.name}"
                        )

                        enriched_system

                      {:error, _reason} ->
                        # If enrichment fails, still use the base MapSystem
                        map_system
                    end
                  else
                    map_system
                  end
                end)

              # Filter for wormhole systems
              wormhole_systems = Enum.filter(systems, &MapSystem.is_wormhole?/1)

              # Log status
              if wormhole_systems == [] do
                Logger.warning("[SystemsClient] No wormhole systems found in map API response")
              else
                Logger.debug("[SystemsClient] Found #{length(wormhole_systems)} wormhole systems")
              end

              # Cache the systems in a way that maintains the MapSystem structs
              CacheRepo.set("map:systems", wormhole_systems, Timings.systems_cache_ttl())

              # Cache just the system IDs for faster lookups
              system_ids = Enum.map(wormhole_systems, & &1.solar_system_id)
              CacheRepo.set("map:system_ids", system_ids, Timings.systems_cache_ttl())

              # Find and notify about new systems
              _ = notify_new_systems(wormhole_systems, cached_systems)

              {:ok, wormhole_systems}

            {:error, reason} ->
              Logger.error("[SystemsClient] Failed to process API response: #{inspect(reason)}")
              {:error, reason}
          end

        {:error, reason} ->
          Logger.error("[SystemsClient] HTTP request failed: #{inspect(reason)}")
          {:error, {:http_error, reason}}
      end
    else
      {:error, reason} ->
        Logger.error("[SystemsClient] Failed to build URL or headers: #{inspect(reason)}")
        {:error, reason}
    end
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
      # Ensure we have both fresh and cached systems as lists
      fresh = fresh_systems || []
      cached = cached_systems || []

      # Find systems that are in fresh but not in cached
      # We compare by id because that's the unique identifier in the map API
      added_systems =
        if cached == [] do
          # If there's no cached systems, this is probably the first run
          # Don't notify about all systems to avoid spamming
          Logger.info(
            "[SystemsClient] No cached systems found; skipping new system notifications on startup"
          )

          []
        else
          # Handle both struct and map types in cached systems
          fresh
          |> Enum.filter(fn fresh_sys ->
            !Enum.any?(cached, fn cached_sys ->
              # Handle comparison for both MapSystem structs and maps
              fresh_id = if is_struct(fresh_sys), do: fresh_sys.id, else: fresh_sys["id"]
              cached_id = if is_struct(cached_sys), do: cached_sys.id, else: cached_sys["id"]

              fresh_id == cached_id
            end)
          end)
        end

      if added_systems != [] do
        Logger.info("[SystemsClient] Found #{length(added_systems)} new systems to notify about")
      end

      # Send notifications for added systems
      for system <- added_systems do
        Task.start(fn ->
          try do
            # Get system name and ID based on struct or map type
            _system_name =
              if is_struct(system, MapSystem) do
                # Log values explicitly to debug name fields
                Logger.info(
                  "[SystemsClient] System before notification - name: #{system.name}, original_name: #{system.original_name}, temporary_name: #{inspect(system.temporary_name)}"
                )

                if system.temporary_name && system.temporary_name != "" do
                  "#{system.temporary_name} (#{system.original_name})"
                else
                  system.name
                end
              else
                temp_name = system["temporary_name"]
                orig_name = system["original_name"]

                # Log values explicitly for map case
                Logger.info(
                  "[SystemsClient] Map system before notification - name: #{system["name"]}, original_name: #{inspect(orig_name)}, temporary_name: #{inspect(temp_name)}"
                )

                if temp_name && temp_name != "" && orig_name && orig_name != "" do
                  "#{temp_name} (#{orig_name})"
                else
                  system["name"] || system["systemName"]
                end
              end

            _system_id =
              if is_struct(system, MapSystem),
                do: system.solar_system_id,
                else: system["systemId"] || system["solar_system_id"]

            # Process the system based on its type and prepare notification data
            # Convert system to MapSystem struct if it's not already
            map_system =
              if is_struct(system, MapSystem) do
                system
              else
                MapSystem.new(system)
              end

            # Check if the system is a wormhole
            if MapSystem.is_wormhole?(map_system) do
              # Get statics info from MapSystem struct
              statics_list = map_system.statics || []

              # Get the system's type description
              type_description = map_system.type_description || "Unknown"

              # Get the class title from MapSystem struct
              class_title = map_system.class_title

              # Log key information found in the system
              Logger.info(
                "[SystemsClient] Processing wormhole system notification - " <>
                  "ID: #{map_system.solar_system_id}, " <>
                  "Name: #{map_system.name}, " <>
                  "Type: #{type_description}, " <>
                  "Class: #{class_title}, " <>
                  "Statics: #{Enum.join(statics_list, ", ")}"
              )
            else
              Logger.info(
                "[SystemsClient] Processing non-wormhole system notification - " <>
                  "ID: #{map_system.solar_system_id}, " <>
                  "Name: #{map_system.name}, " <>
                  "Type: #{map_system.type_description}"
              )
            end

            # Send the notification using the full MapSystem struct
            notifier = NotifierFactory.get_notifier()
            notifier.send_new_system_notification(map_system)
          rescue
            e ->
              Logger.error(
                "[SystemsClient] Error sending system notification: #{inspect(e)}\n#{Exception.format_stacktrace()}"
              )
          end
        end)
      end

      {:ok, added_systems}
    else
      Logger.info("[SystemsClient] System notifications are disabled, skipping")
      {:ok, []}
    end
  end
end
