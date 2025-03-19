defmodule WandererNotifier.Services.SystemTracker do
  @moduledoc """
  Tracks EVE Online solar systems.
  Handles system discovery and notification of new systems.
  """
  require Logger
  alias WandererNotifier.Cache.Repository, as: CacheRepo
  alias WandererNotifier.Api.Http.Client, as: HttpClient
  alias WandererNotifier.Core.Config
  alias WandererNotifier.Core.Features
  alias WandererNotifier.Notifiers.Factory, as: NotifierFactory

  def update_systems(cached_systems \\ nil) do
    Logger.debug("[update_systems] Starting systems update")

    with {:ok, systems_url} <- build_systems_url(),
         {:ok, body} <- fetch_get_body(systems_url),
         {:ok, json} <- decode_json(body),
         {:ok, fresh_systems} <- process_systems(json) do
      if fresh_systems == [] do
        Logger.warning("[update_systems] Received empty system list. Retaining existing cache.")
      else
        # Use provided cached_systems or fetch from cache
        systems_from_cache = if cached_systems != nil, do: cached_systems, else: get_all_systems()

        Logger.debug(
          "[update_systems] Found #{length(fresh_systems)} wormhole systems (previously had #{length(systems_from_cache)})"
        )

        # Log cache details for debugging
        Logger.debug(
          "[update_systems] Cache key: map:systems, cached_systems type: #{inspect(systems_from_cache)}"
        )

        if systems_from_cache != [] do
          new_systems =
            Enum.filter(fresh_systems, fn new_sys ->
              not Enum.any?(systems_from_cache, fn cached ->
                cached["system_id"] == new_sys["system_id"]
              end)
            end)

          if new_systems != [] do
            Logger.info(
              "[update_systems] Found #{length(new_systems)} new systems to notify about"
            )

            Enum.each(new_systems, fn system ->
              send_notification(system)
            end)
          else
            Logger.debug("[update_systems] No new systems found since last update")
          end
        else
          Logger.debug(
            "[update_systems] No cached systems found; skipping new system notifications on startup."
          )
        end

        Logger.debug(
          "[update_systems] Updating systems cache with #{length(fresh_systems)} systems"
        )

        # Store each system individually with its system_id as the key
        Enum.each(fresh_systems, fn system ->
          CacheRepo.set("map:system:#{system["system_id"]}", system, Config.systems_cache_ttl())
        end)

        # Cache just the system IDs for faster lookups
        system_ids = Enum.map(fresh_systems, & &1["system_id"])
        CacheRepo.set("map:system_ids", system_ids, Config.systems_cache_ttl())

        # Also store the full list of systems for backward compatibility
        CacheRepo.set("map:systems", fresh_systems, Config.systems_cache_ttl())
      end

      {:ok, fresh_systems}
    else
      {:error, msg} = err ->
        Logger.error("[update_systems] error: #{inspect(msg)}")
        err
    end
  end

  # Helper function to get all systems from the cache
  defp get_all_systems do
    # Try to get the cached system IDs first (faster lookup)
    system_ids = CacheRepo.get("map:system_ids")

    cond do
      # If we have cached system IDs, use them to fetch systems efficiently with batch get
      is_list(system_ids) and length(system_ids) > 0 ->
        Logger.debug(
          "[get_all_systems] Using #{length(system_ids)} cached system IDs for batch lookup"
        )

        # Construct cache keys for all system IDs
        cache_keys = Enum.map(system_ids, &"map:system:#{&1}")

        # Use batch get to fetch all systems at once
        systems_map = WandererNotifier.Data.Cache.Repository.get_many(cache_keys)

        # Filter out any nil values and return the list of systems
        cache_keys
        |> Enum.map(fn key -> systems_map[key] end)
        |> Enum.filter(& &1)

      # Fallback to the full systems list
      true ->
        case CacheRepo.get("map:systems") do
          nil ->
            []

          systems when is_list(systems) ->
            # Check if we have a list of system objects or just IDs
            if length(systems) > 0 and is_map(List.first(systems)) do
              # We have the full system objects
              systems
            else
              # We have a list of system IDs, use batch get for better performance
              cache_keys = Enum.map(systems, &"map:system:#{&1}")
              systems_map = WandererNotifier.Data.Cache.Repository.get_many(cache_keys)

              cache_keys
              |> Enum.map(fn key -> systems_map[key] end)
              |> Enum.filter(& &1)
            end

          _ ->
            []
        end
    end
  end

  defp build_systems_url do
    Logger.debug("[build_systems_url] Building systems URL from map configuration")

    # Check if the URL has already been cached in the process dictionary
    cached = Process.get(:systems_url_cache)

    if cached != nil do
      {url, cached_env_result} = cached

      # Get the current environment state
      current_env_result = validate_map_env()

      # Compare the cached and current environment results
      if current_env_result == cached_env_result do
        Logger.debug("[build_systems_url] Using cached systems URL: #{url}")
        {:ok, url}
      else
        # Environment changed, rebuild URL
        build_and_cache_url()
      end
    else
      # No cached URL, build it
      build_and_cache_url()
    end
  end

  # Helper to build and cache the URL
  defp build_and_cache_url do
    case validate_map_env() do
      {:ok, map_url} = env_result ->
        # Extract the base URL (without any path segments)
        uri = URI.parse(map_url)
        base_url = "#{uri.scheme}://#{uri.host}#{if uri.port, do: ":#{uri.port}", else: ""}"

        # Get the slug/map name from the path
        slug =
          case uri.path do
            nil ->
              ""

            "/" ->
              ""

            path ->
              # Remove leading slash and get the first path segment
              segments = path |> String.trim_leading("/") |> String.split("/")
              List.first(segments, "")
          end

        # Construct the systems URL with the correct path
        systems_url =
          if slug != "" do
            "#{base_url}/api/map/systems?slug=#{slug}"
          else
            "#{base_url}/api/map/systems"
          end

        # Cache the result with the current environment state
        Process.put(:systems_url_cache, {systems_url, env_result})

        Logger.debug("[build_systems_url] Successfully built systems URL: #{systems_url}")
        {:ok, systems_url}

      {:error, reason} = err ->
        Logger.error("[build_systems_url] Failed to build systems URL: #{inspect(reason)}")
        err
    end
  end

  defp fetch_get_body(url) do
    map_token = Config.map_token()
    headers = if map_token, do: [{"Authorization", "Bearer " <> map_token}], else: []
    label = "SystemTracker"

    HttpClient.get(url, headers, label: label)
    # Don't parse JSON, we'll do that separately
    |> HttpClient.handle_response(false)
  end

  defp decode_json(raw), do: Jason.decode(raw)

  defp process_systems(%{"data" => data}) when is_list(data) do
    Logger.debug("[process_systems] Processing #{length(data)} systems from API response")

    # Check if we should track all systems or just wormhole systems
    track_all_systems = Features.track_all_systems?()
    Logger.debug("[process_systems] TRACK_ALL_SYSTEMS=#{track_all_systems}")

    # Process systems from the map API
    processed =
      Enum.map(data, fn item ->
        with system_id when is_binary(system_id) <- extract_system_id(item),
             {:ok, map_url} <- validate_map_env() do
          # Extract the base URL (without any path segments)
          uri = URI.parse(map_url)
          base_url = "#{uri.scheme}://#{uri.host}#{if uri.port, do: ":#{uri.port}", else: ""}"

          # Get the slug/map name from the path
          slug =
            case uri.path do
              nil ->
                ""

              "/" ->
                ""

              path ->
                # Remove leading slash and get the first path segment
                segments = path |> String.trim_leading("/") |> String.split("/")
                List.first(segments, "")
            end

          # Construct the static info URL with the correct path and slug
          static_info_url =
            if slug != "" do
              "#{base_url}/api/common/system-static-info?id=#{system_id}&slug=#{slug}"
            else
              "#{base_url}/api/common/system-static-info?id=#{system_id}"
            end

          # Get system static info
          case get_or_fetch_system_static_info(static_info_url) do
            {:ok, ssi} ->
              # Extract all the relevant fields from the API response
              original_name = item["original_name"] || item["OriginalName"]
              temporary_name = item["temporary_name"] || item["TemporaryName"]

              # Get region information and statics
              region_name = get_region_for_system(system_id)
              statics = get_statics_for_system(system_id)

              # Check if it's a wormhole system
              is_wormhole = qualifies_as_wormhole?(ssi)
              system_type = if is_wormhole, do: "wormhole", else: "non-wormhole"

              # Extract additional fields from static info
              static_info_data = get_in(ssi, ["data"]) || %{}
              class_title = Map.get(static_info_data, "class_title")
              effect_name = Map.get(static_info_data, "effect_name")
              security = Map.get(static_info_data, "security")
              is_shattered = Map.get(static_info_data, "is_shattered")
              type_description = Map.get(static_info_data, "type_description")
              system_class = Map.get(static_info_data, "system_class")
              solar_system_name = Map.get(static_info_data, "solar_system_name")
              constellation_name = Map.get(static_info_data, "constellation_name")
              wandering = Map.get(static_info_data, "wandering")

              # Only include the system if it's a wormhole or if we're tracking all systems
              if is_wormhole or track_all_systems do
                Logger.debug("[process_systems] Including #{system_type} system: #{system_id}")

                # Create a map with all the relevant fields
                %{
                  "system_id" => system_id,
                  "system_name" =>
                    temporary_name || original_name || solar_system_name ||
                      "Solar System #{system_id}",
                  "original_name" => original_name,
                  "temporary_name" => temporary_name,
                  "region_name" => region_name,
                  "statics" => statics,
                  "is_wormhole" => is_wormhole,
                  "class_title" => class_title,
                  "effect_name" => effect_name,
                  "security" => security,
                  "is_shattered" => is_shattered,
                  "type_description" => type_description,
                  "system_class" => system_class,
                  "constellation_name" => constellation_name,
                  "wandering" => wandering,
                  # Include the full data for reference
                  "data" => static_info_data
                }
              else
                Logger.debug(
                  "[process_systems] Skipping non-wormhole system: #{system_id} (TRACK_ALL_SYSTEMS=false)"
                )

                nil
              end

            _ ->
              # If we can't get static info, include the system only if tracking all systems
              if track_all_systems do
                original_name = item["original_name"] || item["OriginalName"]
                temporary_name = item["temporary_name"] || item["TemporaryName"]

                Logger.debug(
                  "[process_systems] Including system with unknown type: #{system_id} (TRACK_ALL_SYSTEMS=true)"
                )

                %{
                  "system_id" => system_id,
                  "system_name" => temporary_name || original_name || "Solar System #{system_id}",
                  "original_name" => original_name,
                  "temporary_name" => temporary_name,
                  # Assume not a wormhole if we can't determine
                  "is_wormhole" => false
                }
              else
                Logger.debug(
                  "[process_systems] Skipping system with unknown type: #{system_id} (TRACK_ALL_SYSTEMS=false)"
                )

                nil
              end
          end
        else
          _ -> nil
        end
      end)
      # Remove nil entries
      |> Enum.filter(& &1)

    Logger.debug("[process_systems] Processed #{length(processed)} systems after filtering")

    {:ok, processed}
  end

  defp process_systems(_), do: {:ok, []}

  defp extract_system_id(item) do
    case item["solar_system_id"] || item["SolarSystemID"] do
      nil -> nil
      id -> to_string(id)
    end
  end

  defp qualifies_as_wormhole?(ssi) do
    type_description = get_in(ssi, ["data", "type_description"]) || ""
    statics = get_in(ssi, ["data", "statics"]) || []
    length(statics) > 0 or String.starts_with?(type_description, "Class")
  end

  defp get_or_fetch_system_static_info(url) do
    # Extract system_id from the URL
    system_id = extract_system_id_from_url(url)
    cache_key = "static_info:#{system_id}"

    case CacheRepo.get(cache_key) do
      nil ->
        # Cache miss, fetch and cache
        fetch_and_cache_system_info(url, system_id)

      cached when is_binary(cached) ->
        # Valid cache hit
        Jason.decode(cached)

      _ ->
        # Invalid cache value (nil or unexpected type)
        Logger.warning("[Systems] Invalid cache value for #{cache_key}, fetching fresh data")
        fetch_and_cache_system_info(url, system_id)
    end
  end

  defp extract_system_id_from_url(url) do
    uri = URI.parse(url)
    query = URI.decode_query(uri.query || "")
    query["id"]
  end

  defp fetch_and_cache_system_info(url, system_id) do
    map_token = Config.map_token()
    headers = if map_token, do: [{"Authorization", "Bearer " <> map_token}], else: []
    cache_key = "static_info:#{system_id}"

    case HttpClient.request("GET", url, headers) do
      {:ok, %{status_code: 200, body: body}} ->
        CacheRepo.set(cache_key, body, Config.static_info_cache_ttl())
        Jason.decode(body)

      {:ok, %{status_code: status}} ->
        {:error, "Unexpected status: #{status}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp validate_map_env do
    map_url_with_name = Application.get_env(:wanderer_notifier, :map_url_with_name)
    map_url_base = Application.get_env(:wanderer_notifier, :map_url)
    map_name = Application.get_env(:wanderer_notifier, :map_name)

    Logger.debug("[validate_map_env] Validating map configuration:")
    Logger.debug("[validate_map_env] - map_url_with_name: #{inspect(map_url_with_name)}")
    Logger.debug("[validate_map_env] - map_url_base: #{inspect(map_url_base)}")
    Logger.debug("[validate_map_env] - map_name: #{inspect(map_name)}")

    # Determine the final map URL to use
    map_url =
      cond do
        # If MAP_URL_WITH_NAME is set, use it directly
        map_url_with_name && map_url_with_name != "" ->
          Logger.debug("[validate_map_env] Using MAP_URL_WITH_NAME: #{map_url_with_name}")
          map_url_with_name

        # If both MAP_URL and MAP_NAME are set, combine them
        map_url_base && map_url_base != "" && map_name && map_name != "" ->
          url = "#{map_url_base}/#{map_name}"
          Logger.debug("[validate_map_env] Using combined MAP_URL and MAP_NAME: #{url}")
          url

        # If only MAP_URL is set, use it directly
        map_url_base && map_url_base != "" ->
          Logger.debug("[validate_map_env] Using MAP_URL: #{map_url_base}")
          map_url_base

        # No valid URL configuration
        true ->
          Logger.error("[validate_map_env] Map URL is not configured")

          Logger.error(
            "[validate_map_env] Please set MAP_URL_WITH_NAME or both MAP_URL and MAP_NAME environment variables"
          )

          nil
      end

    # Validate the URL
    if map_url do
      uri = URI.parse(map_url)

      cond do
        # Check if the URL has a scheme (http:// or https://)
        uri.scheme == nil ->
          Logger.error(
            "[validate_map_env] Map URL is missing scheme (http:// or https://): #{map_url}"
          )

          {:error, "Map URL is missing scheme"}

        # Check if the URL has a host
        uri.host == nil ->
          Logger.error("[validate_map_env] Map URL is missing host: #{map_url}")
          {:error, "Map URL is missing host"}

        # URL is valid
        true ->
          Logger.debug("[validate_map_env] Map URL is valid: #{map_url}")
          {:ok, map_url}
      end
    else
      {:error, "Map URL is not configured"}
    end
  end

  # Send notification for new system
  defp send_notification(system) do
    if Config.system_notifications_enabled?() do
      NotifierFactory.notify(:send_new_system_notification, [system])
      # Increment the systems counter
      WandererNotifier.Stats.increment(:systems)
    end
  end

  # Helper to get region name for a system
  defp get_region_for_system(system_id) do
    # Try to get static info from cache
    cache_key = "static_info:#{system_id}"

    case CacheRepo.get(cache_key) do
      nil ->
        nil

      cached when is_binary(cached) ->
        case Jason.decode(cached) do
          {:ok, data} ->
            # Extract region information
            _region_id = get_in(data, ["data", "region_id"])
            region_name = get_in(data, ["data", "region_name"])

            if region_name, do: region_name, else: nil

          _ ->
            nil
        end

      _ ->
        nil
    end
  end

  # Helper to get statics for a wormhole system
  defp get_statics_for_system(system_id) do
    # Try to get static info from cache
    cache_key = "static_info:#{system_id}"

    case CacheRepo.get(cache_key) do
      nil ->
        []

      cached when is_binary(cached) ->
        case Jason.decode(cached) do
          {:ok, data} ->
            get_in(data, ["data", "statics"]) || []

          _ ->
            []
        end

      _ ->
        []
    end
  end
end
