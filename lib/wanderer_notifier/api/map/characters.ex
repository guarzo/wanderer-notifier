defmodule WandererNotifier.Api.Map.Characters do
  @moduledoc """
  Tracked characters API calls.
  """
  require Logger
  alias WandererNotifier.Api.Http.Client, as: HttpClient
  alias WandererNotifier.Data.Cache.Repository, as: CacheRepo
  alias WandererNotifier.Core.Config
  alias WandererNotifier.Core.Config.Timings
  alias WandererNotifier.Notifiers.Factory, as: NotifierFactory
  alias WandererNotifier.Helpers.NotificationHelpers

  def update_tracked_characters(cached_characters \\ nil) do
    Logger.debug("[update_tracked_characters] Starting update of tracked characters")

    with {:ok, chars_url} <- build_characters_url(),
         _ <- Logger.debug("[update_tracked_characters] Characters URL built: #{chars_url}"),
         {:ok, body} <- fetch_characters_body(chars_url),
         _ <-
           Logger.debug(
             "[update_tracked_characters] Received response body: #{String.slice(body, 0, 100)}..."
           ),
         {:ok, parsed_chars} <- parse_characters_response(body),
         _ <- update_cache(parsed_chars, cached_characters),
         _ <- notify_new_tracked_characters(parsed_chars, cached_characters) do
      {:ok, parsed_chars}
    else
      error ->
        Logger.error(
          "[update_tracked_characters] Failed to update tracked characters: #{inspect(error)}"
        )

        {:error, error}
    end
  end

  def check_characters_endpoint_availability do
    Logger.debug(
      "[check_characters_endpoint_availability] Checking characters endpoint availability"
    )

    with {:ok, chars_url} <- build_characters_url(),
         _ <-
           Logger.debug(
             "[check_characters_endpoint_availability] Characters URL built: #{chars_url}"
           ),
         {:ok, _body} <- fetch_characters_body(chars_url) do
      Logger.info("[check_characters_endpoint_availability] Characters endpoint is available")
      {:ok, true}
    else
      error ->
        Logger.warning(
          "[check_characters_endpoint_availability] Characters endpoint is NOT available: #{inspect(error)}"
        )

        error_reason =
          case error do
            {:error, reason} -> reason
            other -> "Unexpected error: #{inspect(other)}"
          end

        {:error, error_reason}
    end
  end

  defp build_characters_url do
    base_url_with_slug = Config.map_url()
    map_token = Config.map_token()

    # Validate configuration
    with {:ok, _} <- validate_config(base_url_with_slug, map_token) do
      construct_characters_url(base_url_with_slug)
    end
  end

  defp validate_config(base_url_with_slug, map_token) do
    cond do
      is_nil(base_url_with_slug) or base_url_with_slug == "" ->
        {:error, "Map URL is not configured"}

      is_nil(map_token) or map_token == "" ->
        {:error, "Map token is not configured"}

      true ->
        {:ok, true}
    end
  end

  defp construct_characters_url(base_url_with_slug) do
    # Parse the URL to separate the base URL from the slug
    uri = URI.parse(base_url_with_slug)
    Logger.debug("[build_characters_url] Parsed URI: #{inspect(uri)}")

    # Extract the slug ID from the path
    slug_id = extract_slug_id(uri)
    Logger.debug("[build_characters_url] Extracted slug ID: #{slug_id}")

    # Get base host and construct the final URL
    base_host = get_base_host(uri)
    url = build_final_url(base_host, slug_id)

    Logger.debug("[build_characters_url] Final URL: #{url}")
    {:ok, url}
  end

  defp extract_slug_id(uri) do
    path = uri.path || ""
    path = String.trim_trailing(path, "/")
    Logger.debug("[build_characters_url] Extracted path: #{path}")

    path
    |> String.split("/")
    |> Enum.filter(fn part -> part != "" end)
    |> List.last() || ""
  end

  defp get_base_host(uri) do
    "#{uri.scheme}://#{uri.host}#{if uri.port, do: ":#{uri.port}", else: ""}"
  end

  defp build_final_url(base_host, slug_id) do
    if String.ends_with?(base_host, "/") do
      "#{base_host}api/map/characters?slug=#{URI.encode_www_form(slug_id)}"
    else
      "#{base_host}/api/map/characters?slug=#{URI.encode_www_form(slug_id)}"
    end
  end

  defp fetch_characters_body(chars_url) do
    map_token = Config.map_token()
    # Request headers
    headers = [
      {"Authorization", "Bearer #{map_token}"},
      {"Content-Type", "application/json"},
      {"Accept", "application/json"}
    ]

    Logger.debug("[fetch_characters_body] Requesting from URL: #{chars_url}")

    # Make the request - use only one endpoint, no fallbacks
    case HttpClient.get(chars_url, headers) do
      {:ok, %{status_code: 200, body: body}} ->
        Logger.debug("[fetch_characters_body] Characters API endpoint successful")
        {:ok, body}

      {:ok, %{status_code: status_code, body: body}} ->
        Logger.error(
          "[fetch_characters_body] API returned non-200 status: #{status_code}. Body: #{body}"
        )

        {:error, "API returned non-200 status: #{status_code}"}

      {:error, reason} ->
        Logger.error("[fetch_characters_body] API request failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp parse_characters_response(body) do
    Logger.debug("[parse_characters_response] Raw body: #{body}")

    case Jason.decode(body) do
      {:ok, data} ->
        Logger.debug("[parse_characters_response] Decoded data: #{inspect(data)}")

        case data do
          %{"data" => characters} when is_list(characters) ->
            # API returns a "data" array containing character objects with nested "character" data
            Logger.debug(
              "[parse_characters_response] Parsed characters from data array: #{length(characters)}"
            )

            Logger.debug(
              "[parse_characters_response] First raw character: #{inspect(List.first(characters))}"
            )

            # Transform the characters to match the expected format for the rest of the application
            transformed_characters = Enum.map(characters, &transform_nested_character/1)

            Logger.debug(
              "[parse_characters_response] First transformed character: #{inspect(List.first(transformed_characters))}"
            )

            {:ok, transformed_characters}

          characters when is_list(characters) ->
            # Direct array of characters fallback
            Logger.debug("[parse_characters_response] Parsed characters: #{length(characters)}")

            # Transform the characters to match the expected format for the rest of the application
            transformed_characters = Enum.map(characters, &transform_legacy_character/1)

            {:ok, transformed_characters}

          %{} ->
            # Handle empty response
            Logger.warning(
              "[parse_characters_response] Unexpected response format, no characters found: #{inspect(data)}"
            )

            {:ok, []}

          _ ->
            Logger.error(
              "[parse_characters_response] Unexpected response format: #{inspect(data)}"
            )

            {:error, "Unexpected response format"}
        end

      {:error, reason} ->
        Logger.error(
          "[parse_characters_response] Failed to parse JSON response: #{inspect(reason)}"
        )

        {:error, "Failed to parse JSON response"}
    end
  end

  defp update_cache(new_characters, _cached_characters) do
    CacheRepo.set("map:characters", new_characters, Timings.characters_cache_ttl())
    {:ok, new_characters}
  end

  defp notify_new_tracked_characters(new_characters, cached_characters) do
    # Use the centralized notification determiner to check if character notifications are enabled globally
    if WandererNotifier.Services.NotificationDeterminer.should_notify_character?(nil) do
      # Check if we have both new and cached characters
      new_chars = new_characters || []
      cached_chars = cached_characters || []

      # Find characters that are in new_chars but not in cached_chars
      added_characters = find_new_characters(new_chars, cached_chars)

      # Process each new character for notification
      Enum.each(added_characters, &process_character_notification/1)
    else
      Logger.debug(
        "[notify_new_tracked_characters] Character notifications are disabled globally"
      )
    end

    {:ok, new_characters}
  end

  defp send_character_notification(character_info) do
    notifier = NotifierFactory.get_notifier()
    notifier.send_new_tracked_character_notification(character_info)
  end

  defp transform_legacy_character(char) do
    # Create map with all potential fields
    char_map = %{
      "character_id" => Map.get(char, "id"),
      "name" => Map.get(char, "name"),
      "corporationID" => Map.get(char, "corporation_id"),
      "corporationName" => Map.get(char, "corporation_name"),
      "allianceID" => Map.get(char, "alliance_id"),
      "allianceName" => Map.get(char, "alliance_name")
    }

    # Filter out nil values and return as map
    remove_nil_values(char_map)
  end

  defp remove_nil_values(map) do
    map
    |> Enum.reject(fn {_, v} -> is_nil(v) end)
    |> Map.new()
  end

  defp find_new_characters(_new_chars, []) do
    # If there are no cached characters, this might be the first run
    # In that case, don't notify about all characters to avoid spamming
    []
  end

  defp find_new_characters(new_chars, cached_chars) do
    Enum.filter(new_chars, &new_character?(&1, cached_chars))
  end

  defp new_character?(char, cached_chars) do
    char_id = Map.get(char, "character_id")
    not character_exists_in_cache?(char_id, cached_chars)
  end

  defp character_exists_in_cache?(char_id, cached_chars) do
    Enum.any?(cached_chars, fn c ->
      Map.get(c, "character_id") == char_id
    end)
  end

  defp transform_character_data(character_data) do
    # Create a standardized format for the character
    character_map = %{
      "character_id" => Map.get(character_data, "eve_id"),
      "name" => Map.get(character_data, "name"),
      "corporationID" => Map.get(character_data, "corporation_id"),
      # Using ticker as name
      "corporationName" => Map.get(character_data, "corporation_ticker"),
      "allianceID" => Map.get(character_data, "alliance_id"),
      # Using ticker as name
      "allianceName" => Map.get(character_data, "alliance_ticker")
    }

    # Remove nil values
    remove_nil_values(character_map)
  end

  defp process_character_notification(char) do
    Task.start(fn ->
      try_send_character_notification(char)
    end)
  end

  defp try_send_character_notification(char) do
    try do
      # Extract the character ID
      character_id = NotificationHelpers.extract_character_id(char)
      notify_character_if_needed(character_id, char)
    rescue
      e ->
        Logger.error(
          "[notify_new_tracked_characters] Error sending character notification: #{inspect(e)}"
        )
    end
  end

  defp notify_character_if_needed(character_id, char) do
    determiner = WandererNotifier.Services.NotificationDeterminer

    if determiner.should_notify_character?(character_id) do
      send_notification_for_character(character_id, char)
    else
      Logger.debug(
        "[notify_new_tracked_characters] Character with ID #{character_id} is not marked for notification"
      )
    end
  end

  defp send_notification_for_character(character_id, char) do
    # Create the character notification data structure
    character_info = %{
      "character_id" => character_id,
      "character_name" => NotificationHelpers.extract_character_name(char),
      "corporation_name" => NotificationHelpers.extract_corporation_name(char)
    }

    send_character_notification(character_info)

    Logger.info(
      "[notify_new_tracked_characters] Sent notification for character #{character_info["character_name"]} (ID: #{character_id})"
    )
  end

  defp transform_nested_character(char) do
    # Extract the character data from the nested structure
    character_data = Map.get(char, "character", %{})

    Logger.debug(
      "[parse_characters_response] Character data: #{inspect(character_data)}"
    )

    # Create a standardized format for the character
    transformed = transform_character_data(character_data)

    Logger.debug(
      "[parse_characters_response] Transformed character: #{inspect(transformed)}"
    )

    transformed
  end
end
