defmodule WandererNotifier.Api.CharactersClient do
  @moduledoc """
  Character information API client
  """

  alias WandererNotifier.Api.HttpClient
  alias WandererNotifier.Cache.Keys, as: CacheKeys
  alias WandererNotifier.Cache.Repository, as: CacheRepo
  alias WandererNotifier.Character.Character
  alias WandererNotifier.Api.Map.UrlBuilder
  alias WandererNotifier.Logger.Logger, as: AppLogger
  alias WandererNotifier.Config.Cache
  alias WandererNotifier.Config.Config
  alias WandererNotifier.Notifiers.StructuredFormatter
  alias WandererNotifier.Notifications.Factory, as: NotifierFactory
  alias WandererNotifier.HttpClient.Httpoison, as: HttpClient
  alias WandererNotifier.Map.CharactersClient, as: NewCharactersClient

  @doc """
  Updates tracked character information from the map API.

  ## Parameters
    - cached_characters: List of cached characters for comparison

  ## Returns
    - {:ok, characters} on success
    - {:error, reason} on failure
  """
  def update_tracked_characters(cached_characters) do
    # Delegate to the new implementation
    NewCharactersClient.update_tracked_characters(cached_characters)
  end

  @doc """
  Retrieves character activity data from the map API.

  ## Parameters
    - slug: Optional map slug override
    - days: Number of days of data to get (default 1)

  ## Returns
    - {:ok, data} on success
    - {:error, reason} on failure
  """
  @spec get_character_activity(String.t() | nil, integer()) ::
          {:ok, list(map())} | {:error, term()}
  def get_character_activity(slug \\ nil, days \\ 1) do
    # Delegate to new implementation
    NewCharactersClient.get_character_activity(slug, days)
  end

  @doc """
  Handles successful character response from the API.
  Parses the JSON, validates the data, and processes the characters.

  ## Parameters
    - body: Raw JSON response body
    - cached_characters: Optional list of cached characters for comparison

  ## Returns
    - {:ok, [Character.t()]} on success with a list of Character structs
    - {:error, {:json_parse_error, reason}} if JSON parsing fails
  """
  @spec handle_character_response(String.t(), [Character.t()] | nil) ::
          {:ok, [Character.t()]} | {:error, {:json_parse_error, term()}}
  def handle_character_response(body, cached_characters) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, parsed_json} ->
        process_parsed_character_data(parsed_json, cached_characters)

      {:error, reason} ->
        AppLogger.api_error("⚠️ Failed to parse JSON", error: inspect(reason))
        {:error, {:json_parse_error, reason}}
    end
  rescue
    e ->
      AppLogger.api_error("⚠️ Unexpected error in handle_character_response",
        error: Exception.message(e),
        stacktrace: Exception.format_stacktrace()
      )

      {:error, {:unexpected_error, e}}
  end

  # Process parsed JSON data and extract character information
  defp process_parsed_character_data(parsed_json, cached_characters) do
    # Extract characters data with fallbacks for different API formats
    characters_data = extract_characters_data(parsed_json)
    characters = convert_to_character_structs(characters_data)
    tracked_characters = Enum.filter(characters, & &1.tracked)

    # Cache the characters and handle persistence and notifications
    process_tracked_characters(tracked_characters, cached_characters)

    # Return success with tracked characters
    {:ok, tracked_characters}
  end

  # Extract character data from different JSON structures
  defp extract_characters_data(parsed_json) do
    case parsed_json do
      %{"data" => data} when is_list(data) -> data
      %{"characters" => chars} when is_list(chars) -> chars
      data when is_list(data) -> data
      _ -> []
    end
  end

  # Convert raw character data to Character structs
  defp convert_to_character_structs(characters_data) do
    characters_data
    |> Enum.map(fn raw_char_data ->
      try do
        # First standardize the data
        standardized_data = standardize_character_data(raw_char_data)

        # Create a Character struct from the standardized data
        Character.new(standardized_data)
      rescue
        e ->
          AppLogger.api_error(
            "[CharactersClient] Failed to parse character: #{Exception.message(e)}"
          )

          AppLogger.api_error("[CharactersClient] Character data: #{inspect(raw_char_data)}")

          nil
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  # Standardize character data before conversion to struct
  defp standardize_character_data(raw_char_data) do
    cond do
      has_nested_eve_id?(raw_char_data) -> raw_char_data
      has_top_level_eve_id?(raw_char_data) -> raw_char_data
      has_only_character_id?(raw_char_data) -> handle_missing_eve_id(raw_char_data)
      is_map(raw_char_data) -> handle_missing_required_fields(raw_char_data)
      true -> handle_invalid_data_type(raw_char_data)
    end
  end

  # Check if the data has a nested character with eve_id
  defp has_nested_eve_id?(data) do
    is_map(data) &&
      Map.has_key?(data, "character") &&
      is_map(data["character"]) &&
      Map.has_key?(data["character"], "eve_id")
  end

  # Check if the data has a top-level eve_id field
  defp has_top_level_eve_id?(data) do
    is_map(data) && Map.has_key?(data, "eve_id")
  end

  # Check if the data only has character_id but not eve_id
  defp has_only_character_id?(data) do
    is_map(data) && Map.has_key?(data, "character_id")
  end

  # Handle data with character_id but missing eve_id
  defp handle_missing_eve_id(data) do
    # Log detailed info about problematic data structure
    AppLogger.api_warn(
      "[CharactersClient] Character data has UUID character_id but no eve_id: #{inspect(data)}"
    )

    # Don't try to fix or modify the data - let Character.new raise an appropriate error
    data
  end

  # Handle map data missing required fields
  defp handle_missing_required_fields(data) do
    # Log available keys for debugging
    AppLogger.api_warn(
      "[CharactersClient] Character data missing required fields. " <>
        "Available keys: #{inspect(Map.keys(data))}"
    )

    # Include all data to help debugging
    AppLogger.api_debug("[CharactersClient] Raw character data: #{inspect(data)}")

    # This will result in an error in Character.new, which is what we want
    data
  end

  # Handle invalid data type (non-map)
  defp handle_invalid_data_type(data) do
    AppLogger.api_warn("[CharactersClient] Unexpected character data type: #{inspect(data)}")

    # Let Character.new handle the error
    data
  end

  # Process tracked characters - cache, persist and notify
  defp process_tracked_characters(tracked_characters, cached_characters) do
    # Cache the characters
    cache_ttl = Cache.characters_cache_ttl()

    try do
      # Cache individual characters and build the list
      tracked_characters_list =
        Enum.reduce(tracked_characters, [], fn char, acc ->
          cache_character(char, cache_ttl, acc)
        end)

      # Cache the main character list only after all individual characters are processed
      # Ensure the list is in the same order as the input
      tracked_characters_list = Enum.reverse(tracked_characters_list)
      CacheRepo.set(CacheKeys.character_list(), tracked_characters_list, cache_ttl)

      AppLogger.api_debug(
        "[CharactersClient] Cached main character list with #{length(tracked_characters_list)} characters"
      )

      # Also update the map:characters key for backward compatibility
      CacheRepo.set("map:characters", tracked_characters_list, cache_ttl)
      AppLogger.api_debug("[CharactersClient] Updated map:characters cache for compatibility")

      # Handle persistence and notifications
      handle_character_notifications(tracked_characters_list, cached_characters)
    rescue
      e ->
        AppLogger.api_error(
          "[CharactersClient] Error in process_tracked_characters: #{Exception.message(e)}"
        )

        AppLogger.api_error("[CharactersClient] #{Exception.format_stacktrace()}")
        # Let it crash - the supervisor will handle restart if needed
        reraise e, __STACKTRACE__
    end
  end

  # Cache a single character and return updated accumulator
  defp cache_character(char, cache_ttl, acc) do
    if character_id = char.character_id do
      # Cache individual character
      CacheRepo.set(CacheKeys.character(character_id), char, cache_ttl)
      AppLogger.api_debug("[CharactersClient] Cached character #{character_id}")

      # Mark as tracked
      CacheRepo.set(CacheKeys.tracked_character(character_id), true, cache_ttl)
      AppLogger.api_debug("[CharactersClient] Marked character #{character_id} as tracked")

      # Add to list only if successfully cached
      [char | acc]
    else
      acc
    end
  end

  # Separate function to handle new character notifications with isolated error handling
  defp handle_character_notifications(tracked_characters, cached_characters) do
    notify_new_tracked_characters(tracked_characters, cached_characters)
  rescue
    e ->
      # Log but don't fail the overall operation
      AppLogger.api_error(
        "[CharactersClient] Error notifying new characters: #{Exception.message(e)}"
      )
  end

  @doc """
  Checks if the characters endpoint is available in the current map API.

  ## Returns
    - {:ok, true} if available
    - {:error, reason} if not available
  """
  @spec check_characters_endpoint_availability() :: {:ok, boolean()} | {:error, term()}
  def check_characters_endpoint_availability do
    case UrlBuilder.build_url("map/characters") do
      {:ok, url} ->
        headers = UrlBuilder.get_auth_headers()

        case HttpClient.get(url, headers) do
          {:ok, %{status_code: status}} when status >= 200 and status < 300 ->
            {:ok, true}

          {:ok, %{status_code: status, body: body}} ->
            error_reason = "Endpoint returned status #{status}: #{body}"
            AppLogger.api_warn("⚠️ Characters endpoint error", error: error_reason)
            {:error, error_reason}

          {:error, reason} ->
            AppLogger.api_warn("⚠️ Characters endpoint error", error: inspect(reason))
            {:error, reason}
        end

      {:error, reason} ->
        AppLogger.api_warn("⚠️ Characters endpoint not available", error: inspect(reason))
        {:error, reason}
    end
  end

  @doc """
  Identifies new tracked characters and sends notifications.

  ## Parameters
    - new_characters: List of newly fetched tracked characters
    - cached_characters: List of previously cached characters

  ## Returns
    - {:ok, new_characters} on success with a list of new Character structs
      that were found and notified
    - {:ok, []} if no new characters or notifications are disabled
  """
  @spec notify_new_tracked_characters([Character.t()], [Character.t()] | nil) ::
          {:ok, [Character.t()]}
  def notify_new_tracked_characters(new_characters, cached_characters) do
    # Check if both tracking and notifications are enabled
    if Config.character_tracking_enabled?() && Config.character_notifications_enabled?() do
      # Ensure we have lists to work with
      new_chars = new_characters || []
      cached_chars = cached_characters || []

      # Find characters that are in new_chars but not in cached_chars
      added_characters = find_added_characters(new_chars, cached_chars)

      # Notify about added characters
      notify_characters(added_characters)
    else
      # Return early if tracking or notifications are disabled
      {:ok, []}
    end
  end

  # Find characters that exist in new list but not in cached list
  # No cached chars - first run, don't spam notifications
  defp find_added_characters(_new_chars, []), do: []

  defp find_added_characters(new_chars, cached_chars) do
    # Find characters by their character_id that are in new but not in cached
    new_char_ids = MapSet.new(new_chars, & &1.character_id)
    cached_char_ids = MapSet.new(cached_chars, & &1.character_id)

    # Get the difference (characters in new but not in cached)
    new_ids = MapSet.difference(new_char_ids, cached_char_ids)

    # Return the full character structs for new characters
    Enum.filter(new_chars, fn char -> MapSet.member?(new_ids, char.character_id) end)
  end

  # Send notifications for each new character
  # No new characters
  defp notify_characters([]), do: {:ok, []}

  defp notify_characters(added_characters) do
    AppLogger.api_debug(
      "[CharactersClient] Found #{length(added_characters)} new tracked characters"
    )

    Enum.each(added_characters, &send_character_notification_safely/1)

    {:ok, added_characters}
  end

  # Safely send a notification for a character, handling errors
  defp send_character_notification_safely(character) do
    send_character_notification(character)
  rescue
    e ->
      AppLogger.api_error(
        "[CharactersClient] Failed to send notification for new character: #{inspect(e)}"
      )
  end

  @doc """
  Sends a notification for a new tracked character.
  """
  def send_character_notification(%Character{} = character_data) do
    # Create and send notification
    generic_notification = StructuredFormatter.format_character_notification(character_data)
    discord_format = StructuredFormatter.to_discord_format(generic_notification)

    case NotifierFactory.notify(:send_discord_embed, [discord_format]) do
      {:ok, _} = result ->
        result

      {:error, reason} ->
        AppLogger.api_error("⚠️ Failed to send character notification", error: inspect(reason))
        {:error, reason}
    end
  end

  # Fetch character data from the API
  defp fetch_characters_data(url) do
    headers = UrlBuilder.get_auth_headers()

    case HttpClient.get(url, headers) do
      {:ok, %{status_code: 200, body: body}} when is_binary(body) ->
        {:ok, body}

      {:ok, %{status_code: status_code}} ->
        AppLogger.api_error("⚠️ API returned non-200 status: #{status_code}")
        {:error, {:http_error, status_code}}

      {:error, reason} ->
        AppLogger.api_error("⚠️ HTTP request failed", error: inspect(reason))
        {:error, {:http_error, reason}}
    end
  end
end
