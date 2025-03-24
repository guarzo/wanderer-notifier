defmodule WandererNotifier.Api.Map.Characters do
  @moduledoc """
  Tracked characters API calls.
  """
  alias WandererNotifier.Logger, as: AppLogger
  alias WandererNotifier.Api.Http.Client, as: HttpClient
  alias WandererNotifier.Data.Cache.Repository, as: CacheRepo
  alias WandererNotifier.Core.Config
  alias WandererNotifier.Core.Config.Timings
  alias WandererNotifier.Notifiers.Factory, as: NotifierFactory
  alias WandererNotifier.Helpers.NotificationHelpers

  def update_tracked_characters(cached_characters \\ nil) do
    AppLogger.api_debug("Starting update of tracked characters")

    with {:ok, chars_url} <- build_characters_url(),
         _ <- AppLogger.api_debug("Characters URL built", url: chars_url),
         {:ok, body} <- fetch_characters_body(chars_url),
         _ <-
           AppLogger.api_debug("Received response body", body_preview: String.slice(body, 0, 100)),
         {:ok, parsed_chars} <- parse_characters_response(body),
         _ <- update_cache(parsed_chars, cached_characters),
         _ <- notify_new_tracked_characters(parsed_chars, cached_characters) do
      {:ok, parsed_chars}
    else
      error ->
        AppLogger.api_error("Failed to update tracked characters", error: inspect(error))
        {:error, error}
    end
  end

  def check_characters_endpoint_availability do
    AppLogger.api_debug("Checking characters endpoint availability")

    with {:ok, chars_url} <- build_characters_url(),
         _ <- AppLogger.api_debug("Characters URL built", url: chars_url),
         {:ok, _body} <- fetch_characters_body(chars_url) do
      AppLogger.api_info("Characters endpoint is available")
      {:ok, true}
    else
      error ->
        AppLogger.api_warn("Characters endpoint is NOT available", error: inspect(error))

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
    AppLogger.api_debug("Parsed URI", uri: inspect(uri))

    # Extract the slug ID from the path
    slug_id = extract_slug_id(uri)
    AppLogger.api_debug("Extracted slug ID", slug_id: slug_id)

    # Get base host and construct the final URL
    base_host = get_base_host(uri)
    url = build_final_url(base_host, slug_id)

    AppLogger.api_debug("Final URL constructed", url: url)
    {:ok, url}
  end

  defp extract_slug_id(uri) do
    path = uri.path || ""
    path = String.trim_trailing(path, "/")
    AppLogger.api_debug("Extracted path", path: path)

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

    AppLogger.api_debug("Requesting characters data", url: chars_url)

    # Make the request - use only one endpoint, no fallbacks
    case HttpClient.get(chars_url, headers) do
      {:ok, %{status_code: 200, body: body}} ->
        AppLogger.api_debug("Characters API endpoint successful")
        {:ok, body}

      {:ok, %{status_code: status_code, body: body}} ->
        AppLogger.api_error("API returned non-200 status",
          status_code: status_code,
          body: String.slice(body, 0, 100)
        )

        {:error, "API returned non-200 status: #{status_code}"}

      {:error, reason} ->
        AppLogger.api_error("API request failed", error: inspect(reason))
        {:error, reason}
    end
  end

  defp parse_characters_response(body) do
    AppLogger.api_debug("Processing response body", body_size: byte_size(body))

    case decode_json(body) do
      {:ok, data} -> process_decoded_data(data)
      {:error, reason} -> {:error, reason}
    end
  end

  # Helper to decode JSON with error handling
  defp decode_json(body) do
    case Jason.decode(body) do
      {:ok, data} ->
        AppLogger.api_debug("Successfully decoded JSON", data_keys: map_keys_preview(data))
        {:ok, data}

      {:error, reason} ->
        AppLogger.api_error("Failed to parse JSON response", error: inspect(reason))
        {:error, "Failed to parse JSON response"}
    end
  end

  # Helper to get a preview of map keys for debugging
  defp map_keys_preview(data) when is_map(data) do
    Map.keys(data)
  end

  defp map_keys_preview(data) when is_list(data) do
    "list with #{length(data)} items"
  end

  defp map_keys_preview(_), do: "not a map"

  # Process the decoded data based on format
  defp process_decoded_data(data) do
    cond do
      # Case 1: Nested characters in data array
      is_map(data) && Map.has_key?(data, "data") && is_list(data["data"]) ->
        process_nested_characters(data["data"])

      # Case 2: Direct array of characters
      is_list(data) ->
        process_direct_characters(data)

      # Case 3: Empty or unexpected map
      is_map(data) ->
        AppLogger.api_warn("Unexpected response format, no characters found", data: inspect(data))
        {:ok, []}

      # Case 4: Completely unexpected format
      true ->
        AppLogger.api_error("Unexpected response format", data_type: typeof(data))
        {:error, "Unexpected response format"}
    end
  end

  defp typeof(term) when is_binary(term), do: "string"
  defp typeof(term) when is_boolean(term), do: "boolean"
  defp typeof(term) when is_integer(term), do: "integer"
  defp typeof(term) when is_float(term), do: "float"
  defp typeof(term) when is_map(term), do: "map"
  defp typeof(term) when is_list(term), do: "list"
  defp typeof(term) when is_atom(term), do: "atom"
  defp typeof(term) when is_tuple(term), do: "tuple"
  defp typeof(term) when is_function(term), do: "function"
  defp typeof(term) when is_pid(term), do: "pid"
  defp typeof(term) when is_reference(term), do: "reference"
  defp typeof(_), do: "unknown"

  # Process characters nested in a data array
  defp process_nested_characters(characters) do
    AppLogger.api_debug("Parsed characters from data array", count: length(characters))

    if length(characters) > 0 do
      AppLogger.api_debug("First raw character sample",
        sample: inspect(List.first(characters), limit: 500)
      )
    end

    # Transform the characters to match the expected format
    transformed_characters = Enum.map(characters, &transform_nested_character/1)

    if length(transformed_characters) > 0 do
      AppLogger.api_debug("First transformed character",
        sample: inspect(List.first(transformed_characters), limit: 500)
      )
    end

    {:ok, transformed_characters}
  end

  # Process a direct array of characters
  defp process_direct_characters(characters) do
    AppLogger.api_debug("Parsed characters", count: length(characters))

    # Transform raw characters into standardized format
    transformed_characters = Enum.map(characters, &transform_character_data/1)

    {:ok, transformed_characters}
  end

  defp update_cache(new_characters, _cached_characters) do
    # Update the cache
    CacheRepo.set("map:characters", new_characters, Timings.characters_cache_ttl())

    AppLogger.api_info("Updated characters cache",
      count: length(new_characters),
      ttl: Timings.characters_cache_ttl()
    )

    # Log a sample of characters for debugging
    if length(new_characters) > 0 do
      sample = Enum.take(new_characters, min(2, length(new_characters)))
      AppLogger.api_debug("Sample from updated cache", sample: inspect(sample, limit: 500))
    end

    # Sync with TrackedCharacter Ash resource synchronously - no more background process
    AppLogger.api_info("Starting synchronization with Ash resource")

    # Run sync synchronously
    try do
      case WandererNotifier.Resources.TrackedCharacter.sync_from_cache() do
        {:ok, stats} ->
          AppLogger.api_info("Successfully synced characters to Ash resource",
            stats: inspect(stats)
          )

        {:error, reason} ->
          AppLogger.api_error("Failed to sync characters to Ash resource", error: inspect(reason))
      end
    rescue
      e ->
        AppLogger.api_error("Exception in sync process",
          error: Exception.message(e),
          stacktrace: Exception.format_stacktrace(__STACKTRACE__)
        )
    catch
      kind, reason ->
        AppLogger.api_error("Caught error in sync process",
          kind: kind,
          error: inspect(reason)
        )
    end

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

      AppLogger.api_info("Found new characters", count: length(added_characters))

      # Process each new character for notification
      Enum.each(added_characters, &process_character_notification/1)
    else
      AppLogger.api_debug("Character notifications are disabled globally")
    end

    {:ok, new_characters}
  end

  defp send_character_notification(character_info) do
    notifier = NotifierFactory.get_notifier()
    notifier.send_new_tracked_character_notification(character_info)
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
    # IMPORTANT: Convert eve_id from map API to character_id
    # The map API uses eve_id but our application uses character_id consistently
    # After this transformation, we should never see eve_id again in the application
    eve_id = Map.get(character_data, "eve_id")

    if is_nil(eve_id) do
      AppLogger.api_warn("Character data missing eve_id", data: inspect(character_data))
    end

    character_map = %{
      # Convert eve_id to character_id for consistent field naming in the app
      "character_id" => eve_id,
      "character_name" =>
        Map.get(character_data, "name") || Map.get(character_data, "character_name"),
      "corporation_id" => Map.get(character_data, "corporation_id"),
      "corporation_name" =>
        Map.get(character_data, "corporation_name") ||
          Map.get(character_data, "corporation_ticker"),
      "alliance_id" => Map.get(character_data, "alliance_id"),
      "alliance_name" =>
        Map.get(character_data, "alliance_name") || Map.get(character_data, "alliance_ticker")
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
        AppLogger.api_error("Error sending character notification",
          error: inspect(e),
          stacktrace: Exception.format_stacktrace(__STACKTRACE__)
        )
    end
  end

  defp notify_character_if_needed(character_id, char) do
    determiner = WandererNotifier.Services.NotificationDeterminer

    if determiner.should_notify_character?(character_id) do
      send_notification_for_character(character_id, char)
    else
      AppLogger.api_debug("Character is not marked for notification", character_id: character_id)
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

    AppLogger.api_info("Sent character notification",
      character_name: character_info["character_name"],
      character_id: character_id
    )
  end

  defp transform_nested_character(char) do
    # The API might return data in a nested structure with a "character" key
    # or it might return a flat structure with the data directly in the map
    character_data = Map.get(char, "character", char)

    AppLogger.api_debug("Processing character data", data: inspect(character_data, limit: 500))

    # Transform the data to use consistent field names, prioritizing eve_id
    transform_character_data(character_data)
  end
end
