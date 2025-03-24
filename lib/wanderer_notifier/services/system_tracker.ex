defmodule WandererNotifier.Services.SystemTracker do
  @moduledoc """
  Service for tracking EVE Online systems and their activity.
  Handles fetching, caching, and notifications for systems.
  """

  alias WandererNotifier.Logger, as: AppLogger
  use GenServer

  alias WandererNotifier.Api.Http.Client
  alias WandererNotifier.Api.Http.ErrorHandler
  alias WandererNotifier.Api.Map.SystemsClient
  alias WandererNotifier.Data.MapSystem
  alias WandererNotifier.Api.Map.SystemStaticInfo
  alias WandererNotifier.Core.Config
  alias WandererNotifier.Data.Cache.Repository, as: CacheRepo
  alias WandererNotifier.Notifiers.Factory, as: NotifierFactory

  def update_systems(cached_systems \\ nil) do
    AppLogger.processor_debug("Starting systems update")

    with {:ok, systems_url} <- build_systems_url(),
         {:ok, body} <- fetch_get_body(systems_url),
         {:ok, json} <- decode_json(body),
         {:ok, fresh_systems} <- process_systems(json) do
      process_fresh_systems(fresh_systems, cached_systems)
    else
      {:error, msg} = err ->
        AppLogger.processor_error("Systems update failed", error: inspect(msg))
        err
    end
  end

  # Process the fresh systems data
  defp process_fresh_systems(fresh_systems, cached_systems) do
    if fresh_systems == [] do
      AppLogger.processor_warn("Received empty system list", action: "Retaining existing cache")
      {:ok, fresh_systems}
    else
      # Get and process cached systems
      process_with_cached_systems(fresh_systems, cached_systems)
    end
  end

  # Process fresh systems with cached systems data
  defp process_with_cached_systems(fresh_systems, cached_systems) do
    # Use provided cached_systems or fetch from cache
    systems_from_cache = if cached_systems != nil, do: cached_systems, else: get_all_systems()

    AppLogger.processor_debug("Processing systems update",
      fresh_count: length(fresh_systems),
      cached_count: length(systems_from_cache)
    )

    # Log cache details for debugging
    AppLogger.processor_debug("Cache key information",
      key: "map:systems",
      cached_type: inspect(systems_from_cache)
    )

    # Process new systems if cached systems exist
    if systems_from_cache != [] do
      process_new_systems(fresh_systems, systems_from_cache)
    else
      AppLogger.processor_debug(
        "No cached systems found; skipping new system notifications on startup."
      )
    end

    # Update the cache with fresh systems
    update_systems_cache(fresh_systems)

    {:ok, fresh_systems}
  end

  # Find and process new systems
  defp process_new_systems(fresh_systems, systems_from_cache) do
    # Identify new systems
    new_systems = find_new_systems(fresh_systems, systems_from_cache)

    # Handle notifications for new systems
    if new_systems != [] do
      AppLogger.processor_info("Found new systems to notify about", count: length(new_systems))

      Enum.each(new_systems, &send_notification/1)
    else
      AppLogger.processor_debug("No new systems found since last update")
    end
  end

  # Find systems that are new (not in cached systems)
  defp find_new_systems(fresh_systems, cached_systems) do
    Enum.filter(fresh_systems, fn new_sys ->
      not Enum.any?(cached_systems, fn cached ->
        cached["system_id"] == new_sys["system_id"]
      end)
    end)
  end

  # Update the cache with fresh systems data
  defp update_systems_cache(fresh_systems) do
    AppLogger.processor_debug("Updating systems cache", count: length(fresh_systems))

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

  # Helper function to get all systems from the cache
  defp get_all_systems do
    # Try to get the cached system IDs first (faster lookup)
    system_ids = CacheRepo.get("map:system_ids")

    if is_list(system_ids) and length(system_ids) > 0 do
      # If we have cached system IDs, use them to fetch systems efficiently with batch get
      AppLogger.processor_debug("Using cached system IDs for batch lookup",
        count: length(system_ids)
      )

      # Construct cache keys for all system IDs
      cache_keys = Enum.map(system_ids, &"map:system:#{&1}")

      # Use batch get to fetch all systems at once
      systems_map = WandererNotifier.Data.Cache.Repository.get_many(cache_keys)

      # Filter out any nil values and return the list of systems
      cache_keys
      |> Enum.filter(fn key -> Map.get(systems_map, key) != nil end)
      |> Enum.map(fn key -> Map.get(systems_map, key) end)
    else
      # Fallback to using the all systems cache (may be slower)
      AppLogger.processor_debug("No cached system IDs, using direct cache lookup")
      CacheRepo.get("map:systems") || []
    end
  end

  defp build_systems_url do
    AppLogger.processor_debug("Building systems URL from map configuration")

    # Check if the URL has already been cached in the process dictionary
    cached = Process.get(:systems_url_cache)

    if cached != nil do
      {url, cached_env_result} = cached

      # Get the current environment state
      current_env_result = validate_map_env()

      # Compare the cached and current environment results
      if current_env_result == cached_env_result do
        AppLogger.processor_debug("Using cached systems URL", url: url)
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

        AppLogger.processor_debug("Successfully built systems URL", url: systems_url)
        {:ok, systems_url}

      {:error, reason} = err ->
        AppLogger.processor_error("Failed to build systems URL", error: inspect(reason))
        err
    end
  end

  defp fetch_get_body(url) do
    map_token = Config.map_token()
    headers = if map_token, do: [{"Authorization", "Bearer " <> map_token}], else: []
    label = "SystemTracker"

    Client.get(url, headers)
    |> ErrorHandler.handle_http_response(domain: :map, tag: label)
  end

  defp decode_json(raw), do: Jason.decode(raw)

  # Extract static info URL components from map URL
  defp extract_static_info_url_components(map_url, system_id) do
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

    static_info_url
  end

  # Extract name fields from item
  defp extract_name_fields(item) do
    original_name = item["original_name"] || item["OriginalName"]
    temporary_name = item["temporary_name"] || item["TemporaryName"]
    {original_name, temporary_name}
  end

  # Extract and format system name
  defp format_system_name(temporary_name, original_name, static_info_data, system_id) do
    temporary_name || original_name || Map.get(static_info_data, "solar_system_name") ||
      "Solar System #{system_id}"
  end

  # Extract additional fields from static info data
  defp extract_additional_fields(static_info_data) do
    %{
      "class_title" => Map.get(static_info_data, "class_title"),
      "effect_name" => Map.get(static_info_data, "effect_name"),
      "security" => Map.get(static_info_data, "security"),
      "is_shattered" => Map.get(static_info_data, "is_shattered"),
      "type_description" => Map.get(static_info_data, "type_description"),
      "system_class" => Map.get(static_info_data, "system_class"),
      "constellation_name" => Map.get(static_info_data, "constellation_name"),
      "wandering" => Map.get(static_info_data, "wandering")
    }
  end

  # Create a system map with base fields
  defp create_base_system_map(system_id, system_name, original_name, temporary_name) do
    %{
      "system_id" => system_id,
      "system_name" => system_name,
      "original_name" => original_name,
      "temporary_name" => temporary_name
    }
  end

  # Add wormhole specific fields to system map
  defp add_wormhole_fields(base_map, region_name, statics, is_wormhole, static_info_data) do
    Map.merge(base_map, %{
      "region_name" => region_name,
      "statics" => statics,
      "is_wormhole" => is_wormhole,
      # Include the full data for reference
      "data" => static_info_data
    })
  end

  # Create a system map with all fields
  defp create_system_map(system_info_map) do
    %{
      system_id: system_id,
      system_name: system_name,
      original_name: original_name,
      temporary_name: temporary_name,
      region_name: region_name,
      statics: statics,
      is_wormhole: is_wormhole,
      additional_fields: additional_fields,
      static_info_data: static_info_data
    } = system_info_map

    # Create the base map
    base_map = create_base_system_map(system_id, system_name, original_name, temporary_name)

    # Add wormhole fields
    wormhole_map =
      add_wormhole_fields(base_map, region_name, statics, is_wormhole, static_info_data)

    # Merge in the additional fields
    Map.merge(wormhole_map, additional_fields)
  end

  # Extract system data from API response and static info
  defp extract_system_data(item, system_id, ssi, track_all_systems) do
    # Extract all the relevant fields from the API response
    {original_name, temporary_name} = extract_name_fields(item)

    # Get region information and statics
    region_name = get_region_for_system(system_id)
    statics = get_statics_for_system(system_id)

    # Check if it's a wormhole system
    is_wormhole = qualifies_as_wormhole?(ssi)
    system_type = if is_wormhole, do: "wormhole", else: "non-wormhole"

    # Extract additional fields from static info
    static_info_data = get_in(ssi, ["data"]) || %{}

    # Only include the system if it's a wormhole or if we're tracking all systems
    if is_wormhole or track_all_systems do
      AppLogger.processor_debug("Including system", type: system_type, system_id: system_id)

      # Format system name
      system_name = format_system_name(temporary_name, original_name, static_info_data, system_id)

      # Extract additional fields
      additional_fields = extract_additional_fields(static_info_data)

      # Prepare system info map
      system_info = %{
        system_id: system_id,
        system_name: system_name,
        original_name: original_name,
        temporary_name: temporary_name,
        region_name: region_name,
        statics: statics,
        is_wormhole: is_wormhole,
        additional_fields: additional_fields,
        static_info_data: static_info_data
      }

      # Create the final map
      create_system_map(system_info)
    else
      AppLogger.processor_debug("Skipping non-wormhole system",
        system_id: system_id,
        track_all: false
      )

      nil
    end
  end

  # Create a basic system entry without static info
  defp create_basic_system_entry(item, system_id, track_all_systems) do
    if track_all_systems do
      original_name = item["original_name"] || item["OriginalName"]
      temporary_name = item["temporary_name"] || item["TemporaryName"]

      AppLogger.processor_debug("Including system with unknown type",
        system_id: system_id,
        track_all: true
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
      AppLogger.processor_debug("Skipping system with unknown type",
        system_id: system_id,
        track_all: false
      )

      nil
    end
  end

  # Process a single system item
  defp process_system_item(item, track_all_systems) do
    # First extract the system ID
    system_id = extract_system_id(item)

    # Continue only if we have a valid system ID
    if is_binary(system_id) do
      process_item_with_valid_id(item, system_id, track_all_systems)
    else
      nil
    end
  end

  defp process_item_with_valid_id(item, system_id, track_all_systems) do
    # Validate the map environment
    case validate_map_env() do
      {:ok, map_url} ->
        # Get static info URL and fetch or retrieve the system data
        static_info_url = extract_static_info_url_components(map_url, system_id)
        process_with_static_info(item, system_id, static_info_url, track_all_systems)

      _ ->
        nil
    end
  end

  defp process_with_static_info(item, system_id, static_info_url, track_all_systems) do
    # Get system static info
    case get_or_fetch_system_static_info(static_info_url) do
      {:ok, ssi} ->
        extract_system_data(item, system_id, ssi, track_all_systems)

      _ ->
        create_basic_system_entry(item, system_id, track_all_systems)
    end
  end

  defp process_systems(%{"data" => data}) when is_list(data) do
    AppLogger.processor_debug("Processing systems from API response", %{count: length(data)})

    # Check if we should track all systems or just wormhole systems
    track_all_systems = Config.track_all_systems?()
    AppLogger.processor_debug("Track all systems setting", %{enabled: track_all_systems})

    # Process systems from the map API
    processed =
      data
      |> Enum.map(fn item -> process_system_item(item, track_all_systems) end)
      # Remove nil entries
      |> Enum.filter(& &1)

    AppLogger.processor_debug("Processed systems after filtering", %{count: length(processed)})

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
        AppLogger.processor_warn("Invalid cache value, fetching fresh data", key: cache_key)
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

    case Client.request("GET", url, headers) do
      {:ok, %{status_code: 200, body: body}} ->
        CacheRepo.set(cache_key, body, Config.static_info_cache_ttl())
        Jason.decode(body)

      {:ok, %{status_code: status}} ->
        {:error, status}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Main function to validate map environment variables
  defp validate_map_env do
    # Extract config values
    config = extract_map_config()

    # Determine the URL to use
    map_url = determine_map_url(config)

    # Validate the URL if we have one
    validate_map_url(map_url)
  end

  # Extract map configuration from the environment
  defp extract_map_config do
    %{
      map_url_with_name: Application.get_env(:wanderer_notifier, :map_url_with_name),
      map_url_base: Application.get_env(:wanderer_notifier, :map_url),
      map_name: Application.get_env(:wanderer_notifier, :map_name)
    }
  end

  # Determine the map URL to use based on configuration
  defp determine_map_url(config) do
    # Log configuration values for debugging
    log_map_configuration(config)

    # Choose URL based on available configuration
    choose_url_from_config(config)
  end

  # Log map configuration values
  defp log_map_configuration(config) do
    AppLogger.processor_debug("Validating map configuration:")
    AppLogger.processor_debug("Map URL with name", value: inspect(config.map_url_with_name))
    AppLogger.processor_debug("Map URL base", value: inspect(config.map_url_base))
    AppLogger.processor_debug("Map name", value: inspect(config.map_name))
  end

  # Choose the appropriate URL based on available configuration
  defp choose_url_from_config(config) do
    cond do
      has_url_with_name?(config) ->
        use_url_with_name(config.map_url_with_name)

      has_url_and_name?(config) ->
        combine_url_and_name(config.map_url_base, config.map_name)

      has_url_base?(config) ->
        use_url_base(config.map_url_base)

      true ->
        log_map_config_error()
    end
  end

  # Check if we have a valid URL with name
  defp has_url_with_name?(config) do
    valid_string?(config.map_url_with_name)
  end

  # Check if we have both URL base and name
  defp has_url_and_name?(config) do
    valid_string?(config.map_url_base) && valid_string?(config.map_name)
  end

  # Check if we have just URL base
  defp has_url_base?(config) do
    valid_string?(config.map_url_base)
  end

  # Check if a string is valid (not nil or empty)
  defp valid_string?(str) do
    str && str != ""
  end

  # Use URL with name directly
  defp use_url_with_name(url) do
    AppLogger.processor_debug("Using MAP_URL_WITH_NAME", url: url)
    url
  end

  # Combine URL base and name
  defp combine_url_and_name(base, name) do
    url = "#{base}/#{name}"
    AppLogger.processor_debug("Using combined MAP_URL and MAP_NAME", url: url)
    url
  end

  # Use URL base directly
  defp use_url_base(url) do
    AppLogger.processor_debug("Using MAP_URL", url: url)
    url
  end

  # Log an error when map URL is not configured
  defp log_map_config_error do
    AppLogger.processor_error("Map URL is not configured",
      message: "Please set MAP_URL_WITH_NAME or both MAP_URL and MAP_NAME environment variables"
    )

    nil
  end

  # Validate a map URL
  defp validate_map_url(nil), do: {:error, "Map URL is not configured"}

  defp validate_map_url(map_url) do
    uri = URI.parse(map_url)

    cond do
      # Check if the URL has a scheme (http:// or https://)
      uri.scheme == nil ->
        AppLogger.processor_error("Map URL is missing scheme", url: map_url)
        {:error, "Map URL is missing scheme"}

      # Check if the URL has a host
      uri.host == nil ->
        AppLogger.processor_error("Map URL is missing host", url: map_url)
        {:error, "Map URL is missing host"}

      # URL is valid
      true ->
        AppLogger.processor_debug("Map URL is valid", url: map_url)
        {:ok, map_url}
    end
  end

  # Send notification for new system
  defp send_notification(system) do
    # Skip if notifications are disabled
    if !Config.system_notifications_enabled?() do
      AppLogger.processor_debug("System notifications are disabled")
      return(:ok)
    end

    # Log the system data
    AppLogger.processor_info("Sending notification for system",
      system_data: inspect(system, pretty: true, limit: 2000)
    )

    # Ensure we're working with a MapSystem struct
    enriched_system = prepare_system_for_notification(system)

    # Get system ID for deduplication check
    system_id = extract_system_id_for_notification(enriched_system)

    # Perform deduplication check
    case WandererNotifier.Helpers.DeduplicationHelper.check_and_mark_system(system_id) do
      {:ok, :duplicate} ->
        handle_duplicate_system(system_id)

      {:ok, :new} ->
        send_system_notification(enriched_system, system_id)
    end
  end

  # Return a value early to avoid further processing
  defp return(value), do: value

  # Prepare system for notification by converting to MapSystem struct
  defp prepare_system_for_notification(system) do
    cond do
      # Already a MapSystem struct
      is_struct(system, MapSystem) ->
        AppLogger.processor_info("Using MapSystem struct")
        enrich_system(system)

      # Map with system ID
      is_map(system) ->
        prepare_map_system(system)

      # Unhandled type
      true ->
        AppLogger.processor_warn("Unknown system type", system: inspect(system))
        system
    end
  end

  # Prepare a map system for notification
  defp prepare_map_system(system) do
    system_id = extract_system_id_from_map(system)

    if system_id do
      AppLogger.processor_info("Converting map to MapSystem struct", system_id: system_id)

      # Convert to MapSystem struct and enrich
      system
      |> MapSystem.new()
      |> enrich_system()
    else
      AppLogger.processor_warn("Cannot convert to MapSystem: missing system ID")
      system
    end
  end

  # Extract system ID from a map
  defp extract_system_id_from_map(system) do
    Map.get(system, "solar_system_id") ||
      Map.get(system, :solar_system_id) ||
      Map.get(system, "system_id") ||
      Map.get(system, :system_id)
  end

  # Extract system ID for notification
  defp extract_system_id_for_notification(system) do
    if is_struct(system, MapSystem) do
      system.solar_system_id
    else
      Map.get(system, "system_id") || Map.get(system, "solar_system_id")
    end
  end

  # Handle duplicate system notification
  defp handle_duplicate_system(system_id) do
    AppLogger.processor_info("Skipping duplicate system notification", system_id: system_id)
    :ok
  end

  # Send system notification
  defp send_system_notification(enriched_system, system_id) do
    # Log notification
    AppLogger.processor_info("Processing new system notification", system_id: system_id)

    # Get system name
    system_name = extract_system_name(enriched_system)

    # Prepare notification data
    system_data = %{
      "id" => system_id,
      "name" => system_name,
      "url" => "https://zkillboard.com/system/#{system_id}/",
      "system" => enriched_system
    }

    # Send the notification
    notifier = NotifierFactory.get_notifier()
    notifier.send_new_system_notification(system_data)
  end

  # Extract system name from system object
  defp extract_system_name(system) do
    if is_struct(system, MapSystem) do
      system.name
    else
      Map.get(system, "system_name") ||
        Map.get(system, "name") ||
        "Unknown System"
    end
  end

  # Helper to get region name for a system
  defp get_region_for_system(system_id) do
    # Try to get static info from cache
    cache_key = "static_info:#{system_id}"
    cached_data = CacheRepo.get(cache_key)

    extract_region_from_cached_data(cached_data)
  end

  # Extract region from cached data
  defp extract_region_from_cached_data(nil), do: nil

  defp extract_region_from_cached_data(cached) when is_binary(cached) do
    case Jason.decode(cached) do
      {:ok, data} -> extract_region_from_decoded_data(data)
      _ -> nil
    end
  end

  defp extract_region_from_cached_data(_), do: nil

  # Extract region from decoded JSON data
  defp extract_region_from_decoded_data(data) do
    region_name = get_in(data, ["data", "region_name"])
    if region_name, do: region_name, else: nil
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

  # Helper function to enrich a system with static information
  defp enrich_system(system) do
    if system != nil do
      case SystemStaticInfo.enrich_system(system) do
        {:ok, enriched_system} ->
          AppLogger.processor_debug("Successfully enriched system", name: system.name)
          enriched_system

        {:error, reason} ->
          AppLogger.processor_warn("Failed to enrich system",
            system_name: system.name,
            reason: inspect(reason)
          )

          system
      end
    else
      system
    end
  end

  @impl true
  def init(_args) do
    AppLogger.processor_info("Initializing system tracker service")

    # Schedule the initial systems update
    schedule_systems_update()

    {:ok, %{}}
  end

  @impl true
  def handle_info(:update_systems, state) do
    AppLogger.processor_debug("Starting systems update...")

    # Get existing systems first for comparison
    cached_systems = CacheRepo.get("map:systems") || []

    # Use the SystemsClient to fetch systems
    case SystemsClient.update_systems(cached_systems) do
      {:ok, fresh_systems} ->
        # Note: SystemsClient already handles notifications for new systems

        AppLogger.processor_info("Systems updated successfully", %{count: length(fresh_systems)})

        # Schedule the next update
        schedule_systems_update()
        {:noreply, state}

      {:error, reason} ->
        AppLogger.processor_error("Failed to update systems", error: inspect(reason))

        # Schedule next update even if this one failed
        schedule_systems_update()
        {:noreply, state}
    end
  end

  defp schedule_systems_update do
    # Default to 5 minutes if not configured
    interval = Application.get_env(:wanderer_notifier, :systems_update_interval, 300_000)
    Process.send_after(self(), :update_systems, interval)
  end
end
