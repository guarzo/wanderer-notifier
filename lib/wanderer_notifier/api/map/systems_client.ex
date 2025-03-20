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
            system_name =
              if is_struct(system, MapSystem) do
                if system.temporary_name && system.temporary_name != "" do
                  "#{system.temporary_name} (#{system.original_name})"
                else
                  system.name
                end
              else
                temp_name = system["temporary_name"]
                orig_name = system["original_name"]

                if temp_name && temp_name != "" && orig_name && orig_name != "" do
                  "#{temp_name} (#{orig_name})"
                else
                  system["name"] || system["systemName"]
                end
              end

            system_id =
              if is_struct(system, MapSystem),
                do: system.solar_system_id,
                else: system["systemId"] || system["solar_system_id"]

            # Create base notification data
            system_data = %{
              "name" => system_name,
              "id" => system_id,
              "url" => system_url(system_id),
              # Ensure field is available in both formats
              "solar_system_id" => system_id,
              # Ensure field is available in both formats
              "system_name" => system_name
            }

            # Format additional data based on system type
            system_data =
              if is_struct(system, MapSystem) do
                # Add the system object for easy access to all fields
                system_data = Map.put(system_data, "system", system)

                # Override any existing fields with the system's data for consistency
                system_data =
                  Map.merge(system_data, %{
                    "region_name" => system.region_name,
                    "class_title" => system.class_title,
                    "effect_name" => system.effect_name,
                    "system_type" => Atom.to_string(system.system_type),
                    "original_name" => system.original_name,
                    "temporary_name" => system.temporary_name
                  })

                # Add a staticInfo map structure as expected by Discord notifier
                static_info = %{
                  "typeDescription" =>
                    if(MapSystem.is_wormhole?(system),
                      do: system.class_title || "Wormhole",
                      else: "K-Space"
                    ),
                  "statics" =>
                    format_statics_with_destinations(system.statics, system.static_details),
                  "effectName" => system.effect_name,
                  "regionName" => system.region_name,
                  # Include the raw static_details for the Discord notifier to use
                  "static_details" => system.static_details,
                  # Add class_title to be used in notification titles and text
                  "class_title" => system.class_title
                }

                # Fetch recent kills for the system
                recent_kills = get_recent_kills(system_id)

                Logger.debug(
                  "[SystemsClient] Found #{length(recent_kills)} recent kills for system #{system_id}"
                )

                # Add staticInfo and recent kills to the system data
                system_data
                |> Map.put("staticInfo", static_info)
                |> Map.put("recent_kills", recent_kills)
              else
                # If it's a map, just pass it through with recent kills
                recent_kills = get_recent_kills(system_id)

                Logger.debug(
                  "[SystemsClient] Found #{length(recent_kills)} recent kills for system #{system_id}"
                )

                Map.merge(system_data, %{
                  "system" => system,
                  "recent_kills" => recent_kills
                })
              end

            # Send the notification
            notifier = NotifierFactory.get_notifier()
            notifier.send_new_system_notification(system_data)

            Logger.info("[SystemsClient] New system #{system_name} discovered")
          rescue
            e ->
              Logger.error("[SystemsClient] Error sending system notification: #{inspect(e)}")
          end
        end)
      end

      {:ok, added_systems}
    else
      Logger.debug("[SystemsClient] System notifications disabled")
      {:ok, []}
    end
  end

  # Helper function to generate system URL
  defp system_url(nil), do: nil
  defp system_url(system_id), do: "https://zkillboard.com/system/#{system_id}/"

  # Format statics properly with destination information if available
  defp format_statics_with_destinations(statics, static_details) do
    cond do
      # If we have detailed static information with destinations
      is_list(static_details) && length(static_details) > 0 ->
        # Extract the static names and destinations
        formatted =
          Enum.map(static_details, fn static ->
            # Try to get the destination short name
            destination = Map.get(static, "destination") || Map.get(static, :destination) || %{}
            short_name = Map.get(destination, "short_name") || Map.get(destination, :short_name)

            # Get the static name
            name = Map.get(static, "name") || Map.get(static, :name)

            if short_name && name do
              "#{name} (#{short_name})"
            else
              name
            end
          end)

        # Join the formatted statics with commas
        Enum.join(formatted, ", ")

      # Fall back to basic statics list if no details
      is_list(statics) && length(statics) > 0 ->
        Enum.join(statics, ", ")

      # Default empty string
      true ->
        ""
    end
  end

  # Original format_statics function - keep for compatibility with other code
  defp format_statics(statics) when is_list(statics) do
    Enum.join(statics, ", ")
  end

  defp format_statics(_), do: ""

  # Get region name from MapSystem struct
  defp get_region_name(%MapSystem{} = system) do
    # Try to get region info from the struct
    system.region_name || "Unknown Region"
  end

  # Get region name from map data
  defp get_region_name_from_map(system) when is_map(system) do
    system["region_name"] || "Unknown Region"
  end

  # Get recent kills for a system from zKillboard API
  defp get_recent_kills(system_id) when is_integer(system_id) do
    alias WandererNotifier.Api.Zkill.Client, as: ZkillClient

    try do
      Logger.debug("[SystemsClient] Getting recent kills for system #{system_id}")

      case ZkillClient.get_system_kills(system_id, 5) do
        {:ok, kills} when is_list(kills) ->
          Logger.debug(
            "[SystemsClient] Found #{length(kills)} recent kills for system #{system_id}"
          )

          kills

        {:error, reason} ->
          Logger.warning("[SystemsClient] Failed to get recent kills: #{inspect(reason)}")
          []

        _ ->
          Logger.warning("[SystemsClient] Unexpected response from zKillboard API")
          []
      end
    rescue
      e ->
        Logger.error("[SystemsClient] Exception when getting recent kills: #{inspect(e)}")
        []
    end
  end

  defp get_recent_kills(_), do: []
end
