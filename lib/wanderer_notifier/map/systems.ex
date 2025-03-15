defmodule WandererNotifier.Map.Systems do
  @moduledoc """
  Retrieves and processes system data from the map API, filtering for wormhole systems.
  Only wormhole systems (where a system's static info shows a non-empty "statics" list or
  the "type_description" starts with "Class") are returned.
  """
  require Logger
  alias WandererNotifier.Http.Client, as: HttpClient
  alias WandererNotifier.Cache.Repository, as: CacheRepo
  alias WandererNotifier.Config
  alias WandererNotifier.Config.Timings
  alias WandererNotifier.NotifierFactory

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
        Logger.debug("[update_systems] Found #{length(fresh_systems)} wormhole systems (previously had #{length(systems_from_cache)})")

        # Log cache details for debugging
        Logger.debug("[update_systems] Cache key: map:systems, cached_systems type: #{inspect(systems_from_cache)}")

        if systems_from_cache != [] do
          new_systems =
            Enum.filter(fresh_systems, fn new_sys ->
              not Enum.any?(systems_from_cache, fn cached ->
                cached["system_id"] == new_sys["system_id"]
              end)
            end)

          if new_systems != [] do
            Logger.info("[update_systems] Found #{length(new_systems)} new systems to notify about")
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

        Logger.debug("[update_systems] Updating systems cache with #{length(fresh_systems)} systems")
        # Store each system individually with its system_id as the key
        Enum.each(fresh_systems, fn system ->
          CacheRepo.set("map:system:#{system["system_id"]}", system, Timings.systems_cache_ttl())
        end)
        # Also store the full list of systems for backward compatibility
        CacheRepo.set("map:systems", fresh_systems, Timings.systems_cache_ttl())
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
    case CacheRepo.get("map:systems") do
      nil ->
        []
      systems when is_list(systems) ->
        # Check if we have a list of system objects or just IDs
        if length(systems) > 0 and is_map(List.first(systems)) do
          # We have the full system objects
          systems
        else
          # We have a list of system IDs, fetch each system
          Enum.map(systems, fn system_id ->
            case CacheRepo.get("map:system:#{system_id}") do
              nil -> nil
              system -> system
            end
          end)
          |> Enum.filter(& &1)
        end
      _ ->
        []
    end
  end

  defp build_systems_url do
    Logger.debug("[build_systems_url] Building systems URL from map configuration")

    case validate_map_env() do
      {:ok, map_url} ->
        # Extract the base URL (without any path segments)
        uri = URI.parse(map_url)
        base_url = "#{uri.scheme}://#{uri.host}#{if uri.port, do: ":#{uri.port}", else: ""}"

        # Get the slug/map name from the path
        slug = case uri.path do
          nil -> ""
          "/" -> ""
          path ->
            # Remove leading slash and get the first path segment
            segments = path |> String.trim_leading("/") |> String.split("/")
            List.first(segments, "")
        end

        # Construct the systems URL with the correct path
        systems_url = if slug != "" do
          "#{base_url}/api/map/systems?slug=#{slug}"
        else
          "#{base_url}/api/map/systems"
        end

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

    case HttpClient.request("GET", url, headers) do
      {:ok, %{status_code: 200, body: body}} -> {:ok, body}
      {:ok, %{status_code: status}} -> {:error, "Unexpected status: #{status}"}
      {:error, reason} -> {:error, reason}
    end
  end

  defp decode_json(raw), do: Jason.decode(raw)

  defp process_systems(%{"data" => data}) when is_list(data) do
    Logger.debug("[process_systems] Processing #{length(data)} systems from API response")

    # Determine if we should process all systems or just wormhole systems
    processed = if Config.track_all_systems?() do
      # Process all systems
      Logger.debug("[process_systems] TRACK_ALL_SYSTEMS=true, processing all systems")

      Enum.map(data, fn item ->
        system_id = extract_system_id(item)

        if system_id do
          # Get region information and statics if available
          region_name = get_region_for_system(system_id)
          statics = get_statics_for_system(system_id)

          # Extract names from the item
          original_name = item["original_name"] || item["OriginalName"]
          temporary_name = item["temporary_name"] || item["TemporaryName"]

          # Create a map with all the relevant fields
          %{
            "system_id" => system_id,
            "system_name" => temporary_name || "Solar System #{system_id}",
            "original_name" => original_name,
            "temporary_name" => temporary_name,
            "region_name" => region_name,
            "statics" => statics
          }
        else
          nil
        end
      end)
      |> Enum.filter(& &1) # Remove nil entries
    else
      # Original implementation - filter for wormhole systems only
      Logger.debug("[process_systems] TRACK_ALL_SYSTEMS=false, processing only wormhole systems")

      # Filter for wormhole systems
      wormhole_systems =
        Enum.map(data, &fetch_wormhole_system/1)
        |> Enum.filter(& &1)

      Logger.debug("[process_systems] Found #{length(wormhole_systems)} wormhole systems")

      # Process the wormhole systems
      Enum.map(wormhole_systems, fn sys ->
        # Get region information and statics if available
        region_name = get_region_for_system(sys.system_id)
        statics = get_statics_for_system(sys.system_id)

        # Create a map with all the relevant fields
        %{
          "system_id" => sys.system_id,
          "system_name" => sys.alias || "Solar System #{sys.system_id}",
          "original_name" => sys.original_name,
          "temporary_name" => sys.temporary_name,
          "region_name" => region_name,
          "statics" => statics
        }
      end)
    end

    Logger.debug("[process_systems] Processed #{length(processed)} systems")

    {:ok, processed}
  end

  defp process_systems(_), do: {:ok, []}

  defp fetch_wormhole_system(item) do
    with system_id when is_binary(system_id) <- extract_system_id(item),
         {:ok, map_url} <- validate_map_env() do
      # Extract the base URL (without any path segments)
      uri = URI.parse(map_url)
      base_url = "#{uri.scheme}://#{uri.host}#{if uri.port, do: ":#{uri.port}", else: ""}"

      # Get the slug/map name from the path
      slug = case uri.path do
        nil -> ""
        "/" -> ""
        path ->
          # Remove leading slash and get the first path segment
          segments = path |> String.trim_leading("/") |> String.split("/")
          List.first(segments, "")
      end

      # Construct the static info URL with the correct path and slug
      static_info_url = if slug != "" do
        "#{base_url}/api/common/system-static-info?id=#{system_id}&slug=#{slug}"
      else
        "#{base_url}/api/common/system-static-info?id=#{system_id}"
      end

      case get_or_fetch_system_static_info(static_info_url) do
        {:ok, ssi} ->
          if qualifies_as_wormhole?(ssi) do
            # Extract all the relevant fields from the API response
            original_name = item["original_name"] || item["OriginalName"]
            temporary_name = item["temporary_name"] || item["TemporaryName"]

            # Log the extracted fields for debugging
            Logger.debug("[fetch_wormhole_system] Extracted fields for system_id=#{system_id}: original_name=#{inspect(original_name)}, temporary_name=#{inspect(temporary_name)}")

            %{
              system_id: system_id,
              alias: temporary_name,
              original_name: original_name,
              temporary_name: temporary_name
            }
          else
            nil
          end
        _ ->
          nil
      end
    else
      _ -> nil
    end
  end

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
        CacheRepo.set(cache_key, body, Timings.static_info_cache_ttl())
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
    map_url = cond do
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
        Logger.error("[validate_map_env] Please set MAP_URL_WITH_NAME or both MAP_URL and MAP_NAME environment variables")
        nil
    end

    # Validate the URL
    if map_url do
      uri = URI.parse(map_url)

      cond do
        # Check if the URL has a scheme (http:// or https://)
        uri.scheme == nil ->
          Logger.error("[validate_map_env] Map URL is missing scheme (http:// or https://): #{map_url}")
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
