defmodule WandererNotifier.Api.Map.Systems do
  @moduledoc """
  Retrieves and processes system data from the map API, filtering for wormhole systems.
  Only wormhole systems (where a system's static info shows a non-empty "statics" list or
  the "type_description" starts with "Class") are returned.
  """
  require Logger
  alias WandererNotifier.Api.Http.Client, as: HttpClient
  alias WandererNotifier.Data.Cache.Repository, as: CacheRepo
  alias WandererNotifier.Core.Config
  alias WandererNotifier.Core.Config.Timings
  alias WandererNotifier.Notifiers.Factory, as: NotifierFactory

  def update_systems(cached_systems \\ nil) do
    Logger.debug("[update_systems] Starting systems update")

    with {:ok, systems_url} <- build_systems_url(),
         {:ok, body} <- fetch_get_body(systems_url),
         {:ok, json} <- decode_json(body),
         {:ok, fresh_systems} <- process_systems(json) do
      if fresh_systems == [] do
        Logger.warning("[update_systems] No systems found in map API response")
      else
        Logger.debug("[update_systems] Found #{length(fresh_systems)} systems")
      end

      # Cache the systems - use map:systems key for consistency with helpers
      CacheRepo.set("map:systems", fresh_systems, Timings.systems_cache_ttl())

      # Find new systems by comparing with cached_systems
      _ = notify_new_systems(fresh_systems, cached_systems)

      {:ok, fresh_systems}
    else
      {:error, reason} ->
        Logger.error("[update_systems] Failed to update systems: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp build_systems_url do
    base_url_with_slug = Config.map_url()
    map_token = Config.map_token()

    cond do
      is_nil(base_url_with_slug) or base_url_with_slug == "" ->
        {:error, "Map URL is not configured"}

      is_nil(map_token) or map_token == "" ->
        {:error, "Map token is not configured"}

      true ->
        # Parse the URL to separate the base URL from the slug
        uri = URI.parse(base_url_with_slug)
        Logger.debug("[build_systems_url] Parsed URI: #{inspect(uri)}")

        # Extract the path which contains the slug
        path = uri.path || ""
        path = String.trim_trailing(path, "/")
        Logger.debug("[build_systems_url] Extracted path: #{path}")

        # Extract the slug id from the path
        slug_id =
          path
          |> String.split("/")
          |> Enum.filter(fn part -> part != "" end)
          |> List.last() || ""

        Logger.debug("[build_systems_url] Extracted slug ID: #{slug_id}")

        # Get just the base host without the path
        base_host = "#{uri.scheme}://#{uri.host}#{if uri.port, do: ":#{uri.port}", else: ""}"

        # Construct URL with the slug as a query parameter
        url =
          if String.ends_with?(base_host, "/") do
            "#{base_host}api/map/systems?slug=#{URI.encode_www_form(slug_id)}"
          else
            "#{base_host}/api/map/systems?slug=#{URI.encode_www_form(slug_id)}"
          end

        Logger.info("[build_systems_url] Final URL: #{url}")
        {:ok, url}
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
        Logger.error("[fetch_get_body] API request failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp decode_json(body) do
    case Jason.decode(body) do
      {:ok, json} ->
        {:ok, json}

      {:error, reason} ->
        Logger.error("[decode_json] Failed to decode JSON: #{inspect(reason)}")
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
        Logger.info("[process_systems] Processing systems from data array: #{length(systems)}")
        process_system_list(systems)

      _ ->
        Logger.error("[process_systems] Unexpected JSON format: #{inspect(json)}")
        {:error, "Unexpected JSON format"}
    end
  end
  
  defp process_system_list(systems) do
    # Process systems regardless of which JSON key they came from
    systems_with_static_info =
      # Add staticInfo for each system based on solar_system_id
      Enum.map(systems, fn system ->
        solar_system_id = Map.get(system, "solar_system_id")
        # Create a basic staticInfo structure for all systems
        Map.put(system, "staticInfo", %{
          "statics" => [],
          "typeDescription" => get_system_type(solar_system_id)
        })
      end)
      
    # Filter for wormhole systems
    wormhole_systems =
      systems_with_static_info
      |> Enum.filter(&is_wormhole_system?/1)
      |> Enum.map(&extract_system_data/1)
      
    Logger.info("[process_system_list] Found #{length(wormhole_systems)} wormhole systems out of #{length(systems)} total systems")
    
    {:ok, wormhole_systems}
  end
  
  # Determine system type based on ID
  defp get_system_type(solar_system_id) when is_integer(solar_system_id) do
    # J-space systems have IDs in the 31xxxxxx range
    if solar_system_id >= 31000000 and solar_system_id < 32000000 do
      # Classify based on ID range
      cond do
        solar_system_id < 31000006 -> "Thera"
        solar_system_id < 31001000 -> "Class 1"
        solar_system_id < 31002000 -> "Class 2"
        solar_system_id < 31003000 -> "Class 3"
        solar_system_id < 31004000 -> "Class 4"
        solar_system_id < 31005000 -> "Class 5"
        solar_system_id < 31006000 -> "Class 6"
        true -> "Unknown Wormhole"
      end
    else
      cond do
        solar_system_id < 30000000 -> "Unknown"
        solar_system_id < 30003000 -> "Lowsec" # Approximate
        solar_system_id < 31000000 -> "K-space"
        true -> "Unknown"
      end
    end
  end
  defp get_system_type(_), do: "Unknown"

  defp is_wormhole_system?(system) do
    # First check solar_system_id which is the most reliable indicator
    solar_system_id = Map.get(system, "solar_system_id")
    if is_integer(solar_system_id) and solar_system_id >= 31000000 and solar_system_id < 32000000 do
      true
    else
      # Fall back to checking staticInfo
      case system do
        %{"staticInfo" => %{"statics" => statics}} when is_list(statics) and statics != [] ->
          true

        %{"staticInfo" => %{"typeDescription" => type_desc}} when is_binary(type_desc) ->
          # Check if type description contains any wormhole class indicators
          String.starts_with?(type_desc, "Class") or 
          String.contains?(type_desc, "Thera") or
          String.contains?(type_desc, "Wormhole")

        _ ->
          # Check the name for common wormhole patterns
          name = Map.get(system, "original_name") || Map.get(system, "name") || ""
          String.match?(name, ~r/^J\d{6}$/) # J-space systems have names like J123456
      end
    end
  end

  defp extract_system_data(system) do
    # Extract relevant fields for tracking
    %{
      "id" => Map.get(system, "id"),
      "systemName" => Map.get(system, "systemName"),
      "alias" => Map.get(system, "alias"),
      "systemId" => Map.get(system, "systemId"),
      "staticInfo" => Map.get(system, "staticInfo", %{})
    }
  end

  defp notify_new_systems(fresh_systems, cached_systems) do
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
          []
        else
          fresh
          |> Enum.filter(fn fresh_sys ->
            !Enum.any?(cached, fn cached_sys ->
              Map.get(fresh_sys, "id") == Map.get(cached_sys, "id")
            end)
          end)
        end

      # Send notifications for added systems
      track_all_systems = Config.track_all_systems?()

      for system <- added_systems do
        Task.start(fn ->
          try do
            system_name = Map.get(system, "systemName") || Map.get(system, "alias") || "Unknown"
            system_id = Map.get(system, "systemId")

            # Prepare the notification
            system_data = %{
              "name" => system_name,
              "id" => system_id,
              "url" => system_url(system_id)
            }

            # Send the notification
            notifier = NotifierFactory.get_notifier()
            notifier.send_new_system_notification(system_data)

            if track_all_systems do
              Logger.info(
                "[notify_new_systems] System #{system_name} added and tracked (track_all_systems=true)"
              )
            else
              Logger.info("[notify_new_systems] New system #{system_name} discovered")
            end
          rescue
            e ->
              Logger.error(
                "[notify_new_systems] Error sending system notification: #{inspect(e)}"
              )
          end
        end)
      end

      {:ok, added_systems}
    else
      Logger.debug("[notify_new_systems] System notifications disabled")
      {:ok, []}
    end
  end

  # Helper function to generate system URL
  defp system_url(nil), do: nil
  defp system_url(system_id), do: "https://zkillboard.com/system/#{system_id}/"
end
