defmodule WandererNotifier.Api.Map.Systems do
  @moduledoc """
  Retrieves and processes system data from the map API, filtering for wormhole systems.

  Only wormhole systems (where a system's static info shows a non-empty "statics" list or
  the "type_description" starts with "Class") are returned.

  System type determination priority:
  1. Use API-provided data such as "type_description", "class_title", or "system_class"
  2. Fall back to ID-based classification only when API doesn't provide type information
  """
  require Logger
  alias WandererNotifier.Logger, as: AppLogger
  alias WandererNotifier.Api.Http.Client, as: HttpClient
  alias WandererNotifier.Data.Cache.Repository, as: CacheRepo
  alias WandererNotifier.Core.Config
  alias WandererNotifier.Core.Config.Timings
  alias WandererNotifier.Notifiers.Factory, as: NotifierFactory
  alias WandererNotifier.Config.Features

  def update_systems(cached_systems \\ nil) do
    AppLogger.api_debug("[update_systems] Starting systems update")

    with {:ok, systems_url} <- build_systems_url(),
         {:ok, body} <- fetch_get_body(systems_url),
         {:ok, json} <- decode_json(body),
         {:ok, fresh_systems} <- process_systems(json) do
      if fresh_systems == [] do
        AppLogger.api_warn("[update_systems] No systems found in map API response")
      else
        AppLogger.api_debug("[update_systems] Found #{length(fresh_systems)} systems")
      end

      # Cache the systems - use map:systems key for consistency with helpers
      CacheRepo.set("map:systems", fresh_systems, Timings.systems_cache_ttl())

      # Find new systems by comparing with cached_systems
      _ = notify_new_systems(fresh_systems, cached_systems)

      {:ok, fresh_systems}
    else
      {:error, reason} ->
        AppLogger.api_error("[update_systems] Failed to update systems: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp build_systems_url do
    base_url_with_slug = Config.map_url()
    map_token = Config.map_token()

    # Validate required configuration
    with :ok <- validate_map_url(base_url_with_slug),
         :ok <- validate_map_token(map_token) do
      # Build the URL with validated parameters
      build_url_from_parameters(base_url_with_slug)
    end
  end

  # Validate that map URL is configured
  defp validate_map_url(nil), do: {:error, "Map URL is not configured"}
  defp validate_map_url(""), do: {:error, "Map URL is not configured"}
  defp validate_map_url(_url), do: :ok

  # Validate that map token is configured
  defp validate_map_token(nil), do: {:error, "Map token is not configured"}
  defp validate_map_token(""), do: {:error, "Map token is not configured"}
  defp validate_map_token(_token), do: :ok

  # Build URL from base URL with slug
  defp build_url_from_parameters(base_url_with_slug) do
    # Parse the URL to separate the base URL from the slug
    uri = URI.parse(base_url_with_slug)
    AppLogger.api_debug("[build_systems_url] Parsed URI: #{inspect(uri)}")

    # Extract components
    path = extract_path(uri)
    slug_id = extract_slug_id(path)
    base_host = build_base_host(uri)

    # Construct final URL
    url = build_systems_api_url(base_host, slug_id)

    AppLogger.api_info("[build_systems_url] Final URL: #{url}")
    {:ok, url}
  end

  # Extract the path which contains the slug
  defp extract_path(uri) do
    path = uri.path || ""
    path = String.trim_trailing(path, "/")
    AppLogger.api_debug("[build_systems_url] Extracted path: #{path}")
    path
  end

  # Extract the slug id from the path
  defp extract_slug_id(path) do
    slug_id =
      path
      |> String.split("/")
      |> Enum.filter(fn part -> part != "" end)
      |> List.last() || ""

    AppLogger.api_debug("[build_systems_url] Extracted slug ID: #{slug_id}")
    slug_id
  end

  # Build the base host portion of the URL
  defp build_base_host(uri) do
    "#{uri.scheme}://#{uri.host}#{if uri.port, do: ":#{uri.port}", else: ""}"
  end

  # Build the complete systems API URL
  defp build_systems_api_url(base_host, slug_id) do
    encoded_slug = URI.encode_www_form(slug_id)

    if String.ends_with?(base_host, "/") do
      "#{base_host}api/map/systems?slug=#{encoded_slug}"
    else
      "#{base_host}/api/map/systems?slug=#{encoded_slug}"
    end
  end

  defp fetch_get_body(url) do
    map_token = Config.map_token()
    # Request headers
    headers = [
      {"Authorization", "Bearer #{map_token}"},
      {"Content-Type", "application/json"},
      {"Accept", "application/json"}
    ]

    # Make the request
    case HttpClient.get(url, headers) do
      {:ok, %{status_code: 200, body: body}} ->
        {:ok, body}

      {:ok, %{status_code: status_code, body: body}} ->
        Logger.error(
          "[fetch_get_body] API returned non-200 status: #{status_code}. Body: #{body}"
        )

        {:error, "API returned non-200 status: #{status_code}"}

      {:error, reason} ->
        AppLogger.api_error("[fetch_get_body] API request failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp decode_json(body) do
    case Jason.decode(body) do
      {:ok, json} ->
        {:ok, json}

      {:error, reason} ->
        AppLogger.api_error("[decode_json] Failed to decode JSON: #{inspect(reason)}")
        {:error, "Failed to decode JSON: #{inspect(reason)}"}
    end
  end

  defp process_systems(json) do
    case json do
      %{"systems" => systems} when is_list(systems) ->
        # Handle original API format
        process_system_list(systems)

      %{"data" => systems} when is_list(systems) ->
        # Handle new API format where systems are in a "data" array
        AppLogger.api_info(
          "[process_systems] Processing systems from data array: #{length(systems)}"
        )

        process_system_list(systems)

      _ ->
        AppLogger.api_error("[process_systems] Unexpected JSON format: #{inspect(json)}")
        {:error, "Unexpected JSON format"}
    end
  end

  defp process_system_list(systems) do
    # Process systems regardless of which JSON key they came from
    # Add staticInfo for each system based on solar_system_id
    systems_with_static_info =
      Enum.map(systems, fn system ->
        solar_system_id = Map.get(system, "solar_system_id")

        # Try to use existing API data for type information first
        type_description =
          Map.get(system, "type_description") ||
            Map.get(system, "class_title") ||
            Map.get(system, "system_class")

        # Only use ID-based classification as a fallback
        type_description =
          if type_description do
            type_description
          else
            classify_system_by_id(solar_system_id)
          end

        # Get statics from API data if available
        statics = Map.get(system, "statics") || []

        # Create a staticInfo structure with available data
        Map.put(system, "staticInfo", %{
          "statics" => statics,
          "typeDescription" => type_description
        })
      end)

    # Filter systems based on configuration
    track_all_systems = Features.track_kspace_systems?()

    processed_systems =
      systems_with_static_info
      |> Enum.filter(fn system ->
        # If K-Space tracking is enabled, include all systems
        # Otherwise only include wormhole systems
        track_all_systems || wormhole_system?(system)
      end)
      |> Enum.map(&extract_system_data/1)

    # Log the filtering results
    wormhole_count = Enum.count(systems_with_static_info, &wormhole_system?/1)

    Logger.info(
      "[process_system_list] Tracking #{length(processed_systems)} systems (#{wormhole_count} wormholes) " <>
        "out of #{length(systems)} total systems (tracking K-Space=#{track_all_systems})"
    )

    {:ok, processed_systems}
  end

  # Classifies a system type based on its ID.
  #
  # This function should ONLY be used as a fallback when API data doesn't provide
  # type information. Whenever possible, use the type information provided by the API
  # instead of relying on ID-based classification.
  #
  # J-space (wormhole) systems have IDs in the 31xxxxxx range, and can be further
  # classified by specific ranges within that space.
  defp classify_system_by_id(system_id) when is_binary(system_id) do
    # Try to parse the ID as an integer first
    case Integer.parse(system_id) do
      {id, _} -> classify_system_by_id(id)
      :error -> "Unknown"
    end
  end

  # This function is used as a fallback only when API data doesn't provide type information
  defp classify_system_by_id(id) when is_integer(id) do
    cond do
      wormhole_id?(id) ->
        classify_wormhole(id)

      kspace_id?(id) ->
        classify_kspace(id)

      id < 30_000_000 ->
        "Unknown"

      true ->
        "K-space"
    end
  end

  defp classify_system_by_id(_), do: "Unknown"

  # Check if ID is in wormhole range
  defp wormhole_id?(id) do
    id >= 31_000_000 and id < 32_000_000
  end

  # Check if ID is in k-space range
  defp kspace_id?(id) do
    id >= 30_000_000 and id < 31_000_000
  end

  # Classify wormhole system based on ID range
  defp classify_wormhole(id) do
    cond do
      id < 31_000_006 -> "Thera"
      id < 31_001_000 -> "Class 1"
      id < 31_002_000 -> "Class 2"
      id < 31_003_000 -> "Class 3"
      id < 31_004_000 -> "Class 4"
      id < 31_005_000 -> "Class 5"
      id < 31_006_000 -> "Class 6"
      true -> "Wormhole"
    end
  end

  # Classify k-space system (low-sec or null-sec)
  defp classify_kspace(id) do
    if rem(id, 1000) < 500, do: "Low-sec", else: "Null-sec"
  end

  defp wormhole_system?(system) do
    # Check various indicators to determine if this is a wormhole system
    has_wormhole_id?(system) ||
      has_wormhole_statics?(system) ||
      has_wormhole_type_description?(system) ||
      has_wormhole_name_pattern?(system)
  end

  # Check if the system has an ID in the wormhole range (most reliable indicator)
  defp has_wormhole_id?(system) do
    solar_system_id = Map.get(system, "solar_system_id")

    is_integer(solar_system_id) &&
      solar_system_id >= 31_000_000 &&
      solar_system_id < 32_000_000
  end

  # Check if the system has wormhole statics defined
  defp has_wormhole_statics?(system) do
    case system do
      %{"staticInfo" => %{"statics" => statics}} when is_list(statics) and statics != [] ->
        true

      _ ->
        false
    end
  end

  # Check if the system has a wormhole type description
  defp has_wormhole_type_description?(system) do
    case system do
      %{"staticInfo" => %{"typeDescription" => type_desc}} when is_binary(type_desc) ->
        wormhole_type_description?(type_desc)

      _ ->
        false
    end
  end

  # Check if a type description indicates a wormhole
  defp wormhole_type_description?(type_desc) do
    String.starts_with?(type_desc, "Class") ||
      String.contains?(type_desc, "Thera") ||
      String.contains?(type_desc, "Wormhole")
  end

  # Check if the system name matches wormhole naming patterns
  defp has_wormhole_name_pattern?(system) do
    name = Map.get(system, "original_name") || Map.get(system, "name") || ""
    # J-space systems have names like J123456
    String.match?(name, ~r/^J\d{6}$/)
  end

  defp extract_system_data(system) do
    # Extract relevant fields for tracking, preserving API data where available
    %{
      "id" => Map.get(system, "id"),
      "systemName" => Map.get(system, "systemName"),
      "alias" => Map.get(system, "alias"),
      "systemId" => Map.get(system, "systemId"),
      "staticInfo" => Map.get(system, "staticInfo", %{}),
      # Preserve API-provided type/class information
      "type_description" => Map.get(system, "type_description"),
      "class_title" => Map.get(system, "class_title"),
      "system_class" => Map.get(system, "system_class"),
      "statics" => Map.get(system, "statics", [])
    }
    |> Enum.filter(fn {_, v} -> v != nil end)
    |> Map.new()
  end

  # Find new systems by comparing fresh and cached data
  # If there's no cached systems, this is probably the first run
  defp find_added_systems(_fresh, []), do: []

  defp find_added_systems(fresh, cached) do
    fresh
    |> Enum.filter(&system_not_in_cache?(&1, cached))
  end

  # Check if a system is not in the cache
  defp system_not_in_cache?(fresh_sys, cached) do
    fresh_id = Map.get(fresh_sys, "id")
    !system_id_in_list?(fresh_id, cached)
  end

  # Check if a system ID exists in a list of systems
  defp system_id_in_list?(system_id, system_list) do
    Enum.any?(system_list, fn cached_sys ->
      Map.get(cached_sys, "id") == system_id
    end)
  end

  # Get system name from different possible fields
  defp get_system_name(system) do
    Map.get(system, "systemName") || Map.get(system, "alias") || "Unknown"
  end

  # Add static info to system data
  defp add_static_info(system, system_id) do
    case WandererNotifier.Api.Map.SystemStaticInfo.get_system_static_info(system_id) do
      {:ok, static_info} ->
        AppLogger.api_info(
          "[notify_new_systems] Successfully got static info for system #{system_id}"
        )

        # Extract the full static info data if available
        static_info_data = Map.get(static_info, "data") || %{}

        # Add the rich static info fields directly to the system
        system
        |> Map.put("statics", Map.get(static_info_data, "statics") || [])
        |> Map.put(
          "type_description",
          Map.get(static_info_data, "type_description")
        )
        |> Map.put("class_title", Map.get(static_info_data, "class_title"))
        |> Map.put("effect_name", Map.get(static_info_data, "effect_name"))
        |> Map.put(
          "is_shattered",
          Map.get(static_info_data, "is_shattered")
        )
        |> Map.put("region_name", Map.get(static_info_data, "region_name"))
        |> Map.put("staticInfo", %{
          "typeDescription" =>
            Map.get(static_info_data, "type_description") ||
              Map.get(static_info_data, "class_title") ||
              classify_system_by_id(system_id),
          "statics" => Map.get(static_info_data, "statics") || [],
          "effectName" => Map.get(static_info_data, "effect_name"),
          "isShattered" => Map.get(static_info_data, "is_shattered")
        })

      {:error, reason} ->
        Logger.warning(
          "[notify_new_systems] Failed to get static info for system #{system_id}: #{inspect(reason)}"
        )

        add_fallback_static_info(system, system_id)
    end
  end

  # Add fallback static info when API call fails
  defp add_fallback_static_info(system, system_id) do
    # Try to use existing data first before falling back to ID-based classification
    type_desc =
      Map.get(system, "type_description") ||
        Map.get(system, "class_title") ||
        Map.get(system, "system_class") ||
        classify_system_by_id(system_id)

    Map.put(system, "staticInfo", %{
      "typeDescription" => type_desc,
      "statics" => []
    })
  end

  # Create a basic staticInfo structure for systems without IDs
  defp create_basic_static_info(system) do
    Map.put(system, "staticInfo", %{
      "typeDescription" => "Unknown",
      "statics" => []
    })
  end

  # Prepare system data with static info
  defp prepare_system_data(system, system_name, system_id) do
    if Map.has_key?(system, "staticInfo") do
      # Already has static info, use it directly
      Logger.info(
        "[notify_new_systems] System already has static info: #{inspect(system["staticInfo"])}"
      )

      system
    else
      # Need to enrich the system with static info
      AppLogger.api_info("[notify_new_systems] Enriching system with static info")

      # Try to get static info if we have a valid system ID
      system_with_static =
        if system_id do
          try do
            add_static_info(system, system_id)
          rescue
            e ->
              AppLogger.api_error("[notify_new_systems] Error getting static info: #{inspect(e)}")
              add_fallback_static_info(system, system_id)
          end
        else
          # No system ID, add a basic staticInfo
          create_basic_static_info(system)
        end

      # Ensure we have the name fields set correctly
      system_with_static
      |> Map.put("system_name", system_name)
      |> Map.put("systemName", system_name)
      |> Map.put("name", system_name)
      |> Map.put("system_id", system_id)
      |> Map.put("systemId", system_id)
      |> Map.put("id", system_id)
    end
  end

  # Process notification for a single system
  defp process_system_notification(system, track_all_systems) do
    try do
      system_name = get_system_name(system)
      system_id = Map.get(system, "systemId")

      # Check if this specific system should trigger a notification
      if WandererNotifier.Services.NotificationDeterminer.should_notify_system?(system_id) do
        # Prepare system data with static info
        system_data = prepare_system_data(system, system_name, system_id)

        # Send the notification with the enriched system data
        notifier = NotifierFactory.get_notifier()
        notifier.send_new_system_notification(system_data)

        if track_all_systems do
          Logger.info(
            "[notify_new_systems] System #{system_name} added and tracked (tracking K-Space=true)"
          )
        else
          AppLogger.api_info("[notify_new_systems] New system #{system_name} discovered")
        end
      else
        Logger.debug(
          "[notify_new_systems] System #{system_name} (ID: #{system_id}) is not marked for notification"
        )
      end
    rescue
      e ->
        AppLogger.api_error(
          "[notify_new_systems] Error sending system notification: #{inspect(e)}"
        )
    end
  end

  defp notify_new_systems(fresh_systems, cached_systems) do
    # Use the centralized notification determiner to check if system notifications are enabled
    if WandererNotifier.Services.NotificationDeterminer.should_notify_system?(nil) do
      # Ensure we have both fresh and cached systems as lists
      fresh = fresh_systems || []
      cached = cached_systems || []

      # Find systems that are in fresh but not in cached
      added_systems = find_added_systems(fresh, cached)

      # Send notifications for added systems
      track_all_systems = Features.track_kspace_systems?()

      for system <- added_systems do
        Task.start(fn ->
          process_system_notification(system, track_all_systems)
        end)
      end

      {:ok, added_systems}
    else
      AppLogger.api_debug("[notify_new_systems] System notifications are disabled globally")
      {:ok, []}
    end
  end

  # URL generation is now handled in the systems_client.ex module
end
