defmodule WandererNotifier.Api.Map.Characters do
  @moduledoc """
  Tracked characters API calls.
  """
  alias WandererNotifier.HttpClient.Httpoison, as: HttpClient
  alias WandererNotifier.Config.Config
  alias WandererNotifier.Cache.Helpers, as: CacheHelpers
  alias WandererNotifier.Cache.Keys, as: CacheKeys
  alias WandererNotifier.Cache.Repository, as: CacheRepo
  alias WandererNotifier.Character.Character
  alias WandererNotifier.Logger.Logger, as: AppLogger
  alias WandererNotifier.Notifications.Determiner.Character, as: CharacterDeterminer
  alias WandererNotifier.Notifications.Interface, as: NotificationInterface

  @moduledoc deprecated:
               "This module is deprecated. Use WandererNotifier.Map.CharactersClient instead."

  def update_tracked_characters(cached_characters \\ nil) do
    AppLogger.api_info(
      "[CRITICAL] Characters.update_tracked_characters called, input type: #{typeof(cached_characters)}"
    )

    AppLogger.api_info(
      "[CRITICAL] Stack trace: #{inspect(Process.info(self(), :current_stacktrace), limit: 1000)}"
    )

    AppLogger.api_debug("Starting update of tracked characters")

    # EXTREMELY IMPORTANT: If we're passed a list of processed characters, just return them directly
    # This prevents a duplicate HTTP call when called from CharactersClient
    if is_list(cached_characters) && length(cached_characters) > 0 do
      sample = Enum.at(cached_characters, 0)

      AppLogger.api_info(
        "[CRITICAL] Input is a list of #{length(cached_characters)} items, returning directly. Sample: #{inspect(sample, limit: 200)}"
      )

      update_cache(cached_characters, nil)
      {:ok, cached_characters}
    end

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

  @doc """
  Updates tracked characters using a raw API response body.
  This is the new primary method that should be used by CharactersClient.

  ## Parameters
    - raw_body: The raw API response body as string
    - cached_characters: Optional list of cached characters for comparison

  ## Returns
    - {:ok, characters} on success
    - {:error, reason} on failure
  """
  def update_tracked_characters(raw_body, cached_characters) when is_binary(raw_body) do
    AppLogger.api_info(
      "[CRITICAL] Characters.update_tracked_characters called with raw body, length: #{String.length(raw_body)}"
    )

    # Log sample of the raw body for debugging
    AppLogger.api_debug(
      "Processing raw API response body",
      body_preview: String.slice(raw_body, 0, 150)
    )

    # Process the raw response body
    case parse_characters_response(raw_body) do
      {:ok, parsed_chars} ->
        # Update the cache with the parsed characters
        update_cache(parsed_chars, cached_characters)

        # Check for and notify about new characters
        notify_new_tracked_characters(parsed_chars, cached_characters)

        # Return the parsed characters
        {:ok, parsed_chars}

      {:error, reason} ->
        AppLogger.api_error("Failed to parse character response body", error: inspect(reason))
        {:error, reason}
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
    AppLogger.api_info(
      "[CRITICAL] build_characters_url called, stacktrace: #{inspect(Process.info(self(), :current_stacktrace), limit: 1000)}"
    )

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

  defp update_cache(new_characters, cached_characters) do
    # Get existing characters from cache if not provided - use only one cache source
    current_characters = get_current_characters_from_cache(cached_characters)

    # Log the current state
    AppLogger.api_info(
      "Character cache update",
      current_count: length(current_characters),
      new_count: length(new_characters || [])
    )

    # Merge current and new characters
    merged_characters = merge_characters(current_characters, new_characters)

    # Update the cache with a long TTL (24 hours) for persistence
    update_characters_cache(merged_characters)
    # Return the merged characters
    {:ok, merged_characters}
  rescue
    e ->
      AppLogger.api_error("Exception in update_cache",
        error: Exception.message(e),
        stacktrace: Exception.format_stacktrace(__STACKTRACE__)
      )

      {:error, e}
  end

  # Get current characters from cache, using provided list if available
  defp get_current_characters_from_cache(cached_characters) do
    if is_list(cached_characters) && length(cached_characters) > 0 do
      # Use provided cached characters if available
      cached_characters
    else
      # Otherwise just get from cache directly - this is our single source of truth
      CacheRepo.get(CacheKeys.character_list()) || []
    end
  end

  # Merge current and new characters based on character_id
  defp merge_characters(current_characters, new_characters) do
    # Create a map of character_id -> character for merging
    character_map = build_character_map_from_list(current_characters)

    # Update the map with new characters (overwriting existing ones with same ID)
    updated_map = add_new_characters_to_map(character_map, new_characters)

    # Convert back to a list for the cache
    Map.values(updated_map)
  end

  # Build a map of character_id -> character from a list
  defp build_character_map_from_list(characters) do
    Enum.reduce(characters, %{}, fn char, acc ->
      # Handle both struct and map character types
      char_id =
        if is_struct(char, Character) do
          char.character_id
        else
          Map.get(char, "character_id") || Map.get(char, :character_id)
        end

      if char_id, do: Map.put(acc, char_id, char), else: acc
    end)
  end

  # Add new characters to an existing map
  defp add_new_characters_to_map(map, characters) do
    Enum.reduce(characters || [], map, fn char, acc ->
      # Handle both struct and map character types
      char_id =
        if is_struct(char, Character) do
          char.character_id
        else
          Map.get(char, "character_id") || Map.get(char, :character_id)
        end

      if char_id, do: Map.put(acc, char_id, char), else: acc
    end)
  end

  # Update the cache with the merged characters list
  defp update_characters_cache(merged_characters) do
    # Use a long TTL (24 hours) for persistence
    long_ttl = 86_400

    # Update the cache
    CacheRepo.set(CacheKeys.character_list(), merged_characters, long_ttl)

    # Cache individual characters and mark them as tracked
    Enum.each(merged_characters, fn char ->
      char_id = char.character_id

      if char_id do
        # Cache individual character
        CacheRepo.set(CacheKeys.character(char_id), char, long_ttl)
        # Mark as tracked
        CacheHelpers.add_character_to_tracked(char_id, char)
      end
    end)

    # Verify the update (with brief delay to ensure it's written)
    Process.sleep(50)
    post_update_count = length(CacheRepo.get(CacheKeys.character_list()) || [])

    AppLogger.api_info(
      "Character cache updated",
      final_count: post_update_count,
      expected_count: length(merged_characters)
    )
  end

  defp notify_new_tracked_characters(new_characters, cached_characters) do
    # Use the CharacterDeterminer to check if character notifications are enabled globally
    if CharacterDeterminer.should_notify?(nil, %{}) do
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
    AppLogger.api_info("Sending notification for new character: #{character_info.name}")
    NotificationInterface.send_message(character_info)
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
    # Get character_id from either struct or map
    char_id =
      if is_struct(char, Character) do
        char.character_id
      else
        Map.get(char, "character_id") || Map.get(char, :character_id)
      end

    not character_exists_in_cache?(char_id, cached_chars)
  end

  defp character_exists_in_cache?(char_id, cached_chars) do
    Enum.any?(cached_chars, fn c ->
      # Get the character_id from either a struct or map
      c_id =
        if is_struct(c, Character) do
          c.character_id
        else
          Map.get(c, "character_id") || Map.get(c, :character_id)
        end

      c_id == char_id
    end)
  end

  defp transform_character_data(character_data) do
    # CRITICAL: We must use eve_id from the API as our character_id
    # The API returns both a UUID-style ID (which we ignore) and a numeric eve_id (which we use)
    eve_id = Map.get(character_data, "eve_id")

    # Log detailed character ID information for debugging
    AppLogger.api_debug(
      "Character ID conversion",
      eve_id: eve_id,
      uuid_char_id: Map.get(character_data, "character_id"),
      id: Map.get(character_data, "id"),
      all_keys: Map.keys(character_data)
    )

    if is_nil(eve_id) do
      # This is a critical warning - we can't process characters without a valid eve_id
      AppLogger.api_warn(
        "[Characters] Character data missing eve_id - cannot process correctly",
        character_data: inspect(character_data, limit: 200)
      )

      nil
    else
      # Create a Character struct directly with the required fields
      %Character{
        character_id: eve_id,
        name: Map.get(character_data, "name"),
        corporation_id: character_data["corporation_id"],
        corporation_ticker: character_data["corporation_ticker"],
        alliance_id: character_data["alliance_id"],
        alliance_ticker: character_data["alliance_ticker"],
        tracked: Map.get(character_data, "tracked", true)
      }
    end
  end

  defp process_character_notification(char) do
    Task.start(fn ->
      try_send_character_notification(char)
    end)
  end

  defp try_send_character_notification(char) do
    # Extract the character ID
    character_id = Map.get(char, :character_id)
    notify_character_if_needed(character_id, char)
  rescue
    e ->
      AppLogger.api_error("Error sending character notification",
        error: inspect(e),
        stacktrace: Exception.format_stacktrace(__STACKTRACE__)
      )
  end

  defp notify_character_if_needed(character_id, char) do
    if CharacterDeterminer.should_notify?(character_id, %{}) do
      send_notification_for_character(character_id, char)
    else
      AppLogger.api_debug("Character is not marked for notification", character_id: character_id)
    end
  end

  defp send_notification_for_character(character_id, char) do
    # Create the character notification data structure
    character_info = %{
      "character_id" => character_id,
      "character_name" => char.name,
      "corporation_name" => char.corporation_ticker || char.corporation_name || "Unknown"
    }

    send_character_notification(character_info)

    AppLogger.api_info("Sent character notification",
      character_name: character_info["character_name"],
      character_id: character_id
    )
  end

  defp transform_nested_character(char) do
    # The API returns data in a nested structure with a "character" key
    # Get the nested character data
    character_data = Map.get(char, "character")

    # Log what we're working with for debugging
    AppLogger.api_debug("Processing nested character data",
      has_nested_character: Map.has_key?(char, "character"),
      nested_keys: Map.keys(character_data || %{}),
      has_eve_id: Map.has_key?(character_data || %{}, "eve_id"),
      eve_id: Map.get(character_data || %{}, "eve_id")
    )

    if is_nil(character_data) do
      AppLogger.api_error(
        "Missing character data in nested structure - this is critical. API format may have changed.",
        char: inspect(char, limit: 200)
      )

      nil
    else
      # Extract the critical eve_id from nested data
      eve_id = Map.get(character_data, "eve_id")

      if is_nil(eve_id) do
        AppLogger.api_error(
          "Missing eve_id in character data - this is critical. API format may have changed.",
          character_data: inspect(character_data, limit: 200)
        )

        nil
      else
        # Create a Character struct directly with the fields from the nested structure
        # Also incorporate top-level fields like "tracked" if present
        %Character{
          character_id: eve_id,
          name: Map.get(character_data, "name"),
          corporation_id: character_data["corporation_id"],
          corporation_ticker: character_data["corporation_ticker"],
          alliance_id: character_data["alliance_id"],
          alliance_ticker: character_data["alliance_ticker"],
          tracked: Map.get(char, "tracked", true)
        }
      end
    end
  end
end
