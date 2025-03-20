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

            system_id =
              if is_struct(system, MapSystem),
                do: system.solar_system_id,
                else: system["systemId"] || system["solar_system_id"]

            # Format system data for notification
            system_data = %{
              "name" => system_name,
              "id" => system_id,
              "url" => "https://evemaps.dotlan.net/system/#{URI.encode_www_form(system_name)}",
              # Add the full system object
              "system" => system
            }

            # Process the system based on its type and prepare notification data
            updated_system_data =
              if is_struct(system) do
                # Handle MapSystem struct format - format data
                region_name = get_region_name(system)

                # Add additional data for the system based on type
                system_data =
                  Map.merge(system_data, %{
                    "region_name" => region_name,
                    "class_title" => system.class_title,
                    "effect_name" => system.effect_name,
                    "system_type" =>
                      if(MapSystem.is_wormhole?(system), do: "wormhole", else: "k-space"),
                    "original_name" => system.original_name,
                    "temporary_name" => system.temporary_name,
                    "solar_system_id" => system.solar_system_id
                  })

                # Create structured static_info for Discord notifier to use
                static_info = %{
                  "typeDescription" =>
                    if(MapSystem.is_wormhole?(system),
                      do: system.class_title || "Wormhole",
                      else: "K-Space"
                    ),
                  "statics" =>
                    format_statics_with_destinations(system.statics, system.static_details),
                  "effectName" => system.effect_name || "",
                  "regionName" => region_name,
                  # Include the raw static_details for the Discord notifier to use
                  "static_details" => system.static_details,
                  # Add class_title to be used in notification titles and text
                  "class_title" => system.class_title
                }

                # Fetch recent kills for the system
                recent_kills = get_recent_kills(system.solar_system_id)

                Logger.info(
                  "[SystemsClient] Found #{length(recent_kills)} recent kills for system #{system.solar_system_id}"
                )

                # Add staticInfo and recent kills to the system data
                system_data
                |> Map.put("staticInfo", static_info)
                |> Map.put("recent_kills", recent_kills)
                |> (fn data ->
                      # Verify original_name is being preserved
                      Logger.info(
                        "[SystemsClient] Original name in struct case: #{system.original_name}"
                      )

                      data
                    end).()
              else
                # If it's a map, just pass it through with recent kills
                system_id = system["solar_system_id"] || system["system_id"] || system["systemId"]

                # Convert system_id to integer if it's a string
                system_id =
                  if is_binary(system_id) do
                    case Integer.parse(system_id) do
                      {num, _} -> num
                      :error -> nil
                    end
                  else
                    system_id
                  end

                # Fetch recent kills if we have a valid system_id
                recent_kills = if is_integer(system_id), do: get_recent_kills(system_id), else: []

                Logger.info(
                  "[SystemsClient] Found #{length(recent_kills)} recent kills for non-struct system #{system_id}"
                )

                # Ensure we include system_id for kill lookups
                updated_data =
                  Map.merge(system_data, %{
                    "system" => system,
                    "recent_kills" => recent_kills,
                    "solar_system_id" => system_id
                  })

                Logger.info(
                  "[SystemsClient] Notification data keys: #{inspect(Map.keys(updated_data))}"
                )

                # Verify original_name is preserved
                if Map.get(system, "original_name") do
                  Logger.info(
                    "[SystemsClient] Original name is present in system: #{Map.get(system, "original_name")}"
                  )
                end

                updated_data
              end

            # Send the notification
            notifier = NotifierFactory.get_notifier()
            notifier.send_new_system_notification(updated_system_data)

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

  # Get region name from MapSystem struct
  defp get_region_name(%MapSystem{} = system) do
    # Try to get region info from the struct
    system.region_name || "Unknown Region"
  end

  # Get recent kills for a system from zKillboard API
  defp get_recent_kills(system_id) when is_integer(system_id) do
    alias WandererNotifier.Api.ZKill.Service, as: ZkillService

    try do
      Logger.info("[SystemsClient] Getting recent kills for system #{system_id}")

      case ZkillService.get_system_kills(system_id, 5) do
        {:ok, kills} when is_list(kills) ->
          Logger.info(
            "[SystemsClient] Found #{length(kills)} recent kills for system #{system_id}"
          )

          if length(kills) > 0 do
            kill_ids = Enum.map(kills, &Map.get(&1, "killmail_id"))
            Logger.info("[SystemsClient] Kill IDs: #{inspect(kill_ids)}")
          end

          kills

        {:error, reason} ->
          Logger.warning("[SystemsClient] Failed to get recent kills: #{inspect(reason)}")
          []

        other ->
          Logger.warning(
            "[SystemsClient] Unexpected response from zKillboard API: #{inspect(other)}"
          )

          []
      end
    rescue
      e ->
        Logger.error("[SystemsClient] Exception when getting recent kills: #{inspect(e)}")
        stacktrace = Process.info(self(), :current_stacktrace)
        Logger.error("[SystemsClient] Stacktrace: #{inspect(stacktrace)}")
        []
    end
  end

  defp get_recent_kills(_), do: []
end
