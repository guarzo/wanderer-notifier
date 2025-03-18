defmodule WandererNotifier.Services.CharTracker do
  @moduledoc """
  Tracks EVE Online characters.
  Handles character discovery and notification of new characters.
  """
  require Logger
  alias WandererNotifier.Cache.Repository, as: CacheRepo
  alias WandererNotifier.Api.Http.Client, as: HttpClient
  alias WandererNotifier.Core.Config
  alias WandererNotifier.Notifiers.Factory, as: NotifierFactory
  alias WandererNotifier.Config.Timings
  alias WandererNotifier.Helpers.NotificationHelpers

  def update_tracked_characters(cached_characters \\ nil) do
    Logger.debug("[update_tracked_characters] Starting update of tracked characters")

    with {:ok, chars_url} <- build_characters_url(),
         _ <- Logger.debug("[update_tracked_characters] Characters URL built: #{chars_url}"),
         {:ok, body} <- fetch_characters_body(chars_url),
         _ <- Logger.debug("[update_tracked_characters] Received response body: #{String.slice(body, 0, 100)}..."),
         {:ok, json} <- decode_json(body),
         _ <- Logger.debug("[update_tracked_characters] Successfully decoded JSON response"),
         {:ok, tracked} <- process_characters(json) do

      # Get the cached characters and log details
      characters_from_cache = if cached_characters != nil, do: cached_characters, else: CacheRepo.get("map:characters") || []
      Logger.debug("[update_tracked_characters] Found #{length(tracked)} tracked characters (previously had #{length(characters_from_cache)})")

      if characters_from_cache != [] do
        new_tracked =
          Enum.filter(tracked, fn new_char ->
            not Enum.any?(characters_from_cache, fn old_char ->
              old_char["character_id"] == new_char["character_id"]
            end)
          end)

        if new_tracked != [] do
          Logger.info("[update_tracked_characters] Found #{length(new_tracked)} new characters to notify about")

          Enum.each(new_tracked, fn character ->
            char_name = Map.get(character, "character_name", "Unknown")
            char_id = Map.get(character, "character_id", "Unknown")
            Logger.info("[update_tracked_characters] Sending notification for new character: #{char_name} (ID: #{char_id})")
            send_notification(character)
          end)
        else
          Logger.debug("[update_tracked_characters] No new characters found since last update")
        end
      else
        Logger.debug(
          "[update_tracked_characters] No cached characters found; skipping notifications on startup."
        )
      end

      Logger.debug("[update_tracked_characters] Updating characters cache with #{length(tracked)} characters")
      CacheRepo.set("map:characters", tracked, Timings.characters_cache_ttl())

      {:ok, tracked}
    else
      {:error, msg} = err ->
        Logger.error("[update_tracked_characters] error: #{inspect(msg)}")
        err
    end
  end

  defp build_characters_url do
    Logger.debug("[build_characters_url] Building characters URL from map configuration")

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

        # Construct the characters URL with the correct path
        characters_url = if slug != "" do
          "#{base_url}/api/map/characters?slug=#{slug}"
        else
          "#{base_url}/api/map/characters"
        end

        Logger.debug("[build_characters_url] Successfully built characters URL: #{characters_url}")
        {:ok, characters_url}

      {:error, reason} = err ->
        Logger.error("[build_characters_url] Failed to build characters URL: #{inspect(reason)}")
        err
    end
  end

  defp fetch_characters_body(url) do
    map_token = Config.map_token()

    headers =
      if map_token do
        Logger.debug("[fetch_characters_body] Using authorization token: #{String.slice(map_token, 0, 8)}...")
        [{"Authorization", "Bearer " <> map_token}]
      else
        Logger.warning("[fetch_characters_body] No map token configured, making unauthenticated request")
        []
      end

    Logger.debug("[fetch_characters_body] Making request to: #{url}")
    label = "CharTracker.fetch_characters"

    HttpClient.get(url, headers, [label: label, debug: true])
    |> HttpClient.handle_response(false) # Don't parse JSON, we'll do that separately
  end

  defp decode_json(raw) do
    case Jason.decode(raw) do
      {:ok, data} -> {:ok, data}
      error -> {:error, error}
    end
  end

  defp process_characters(%{"data" => data}) when is_list(data) do
    # Log the raw data structure for debugging
    Logger.debug("[process_characters] Raw data structure: #{inspect(data, pretty: true, limit: 5000)}")

    tracked =
      data
      |> Enum.filter(fn item -> Map.get(item, "tracked") == true end)
      |> Enum.map(fn item ->
        char_info = item["character"] || %{}

        # Log the character info for debugging
        Logger.debug("[process_characters] Processing character: #{inspect(char_info, pretty: true)}")

        # Extract the EVE ID using the helper
        eve_id = NotificationHelpers.extract_character_id(char_info)

        # Skip characters without a valid EVE ID
        if is_nil(eve_id) do
          Logger.warning("[process_characters] Skipping character without valid EVE ID: #{inspect(char_info, pretty: true)}")
          nil
        else
          # Create a map with the necessary fields, ensuring we preserve the original structure
          # but also add flattened fields for easier access
          character_map = %{
            # Store the original character data
            "character" => char_info,

            # Add flattened fields for easier access - use only the numeric EVE ID
            "character_id" => eve_id,
            "eve_id" => eve_id,
            "character_name" => char_info["name"] || char_info["character_name"],
            "corporation_id" => char_info["corporation_id"],
            "alliance_id" => char_info["alliance_id"]
          }

          # Add corporation_name if available
          character_map = if char_info["corporation_name"] do
            Logger.debug("[process_characters] Found corporation_name in data: #{char_info["corporation_name"]}")
            Map.put(character_map, "corporation_name", char_info["corporation_name"])
          else
            character_map
          end

          # Log the final character map for debugging
          Logger.debug("[process_characters] Final character map: #{inspect(character_map, pretty: true)}")

          character_map
        end
      end)
      |> Enum.filter(&(&1 != nil)) # Remove nil entries (characters without valid EVE IDs)

    {:ok, tracked}
  end

  defp process_characters(_), do: {:ok, []}

  def validate_map_env do
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

  @doc """
  Checks if the characters endpoint is available by making a test request.
  This can be used to diagnose issues with the characters API.
  """
  def check_characters_endpoint_availability do
    with {:ok, chars_url} <- build_characters_url() do
      map_token = Config.map_token()
      headers =
        if map_token do
          [{"Authorization", "Bearer " <> map_token}]
        else
          []
        end

      # First try a HEAD request to check if the endpoint exists
      Logger.debug("[check_characters_endpoint_availability] Making HEAD request to: #{chars_url}")
      head_result = HttpClient.request("HEAD", chars_url, headers)

      case head_result do
        {:ok, %{status_code: status}} when status in 200..299 ->
          Logger.debug("[check_characters_endpoint_availability] Characters endpoint is available (status: #{status})")
          {:ok, "Characters endpoint is available"}

        {:ok, %{status_code: 404}} ->
          Logger.error("[check_characters_endpoint_availability] Characters endpoint not found (404)")
          Logger.error("[check_characters_endpoint_availability] This map API may not support character tracking")

          # Try to get the API root to see what endpoints are available
          uri = URI.parse(chars_url)
          api_root_url = "#{uri.scheme}://#{uri.host}#{if uri.port, do: ":#{uri.port}", else: ""}/api"
          Logger.debug("[check_characters_endpoint_availability] Checking API root at: #{api_root_url}")

          case HttpClient.request("GET", api_root_url, headers) do
            {:ok, %{status_code: 200, body: body}} ->
              Logger.debug("[check_characters_endpoint_availability] API root is available")
              Logger.debug("[check_characters_endpoint_availability] API response: #{body}")
              {:error, "Characters endpoint not found, but API root is available"}

            _ ->
              {:error, "Characters endpoint not found (404)"}
          end

        {:ok, %{status_code: status}} ->
          Logger.error("[check_characters_endpoint_availability] Unexpected status: #{status}")
          {:error, "Unexpected status: #{status}"}

        {:error, reason} ->
          Logger.error("[check_characters_endpoint_availability] Request error: #{inspect(reason)}")
          {:error, reason}
      end
    else
      {:error, reason} = err ->
        Logger.error("[check_characters_endpoint_availability] Failed to build characters URL: #{inspect(reason)}")
        err
    end
  end

  # Send notification for new character
  defp send_notification(character) do
    if Config.character_notifications_enabled?() do
      NotifierFactory.notify(:send_new_tracked_character_notification, [character])
      # Increment the character counter
      WandererNotifier.Stats.increment(:characters)
    end
  end
end
