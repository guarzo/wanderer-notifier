defmodule WandererNotifier.Api.Map.CharactersClient do
  @moduledoc """
  Client for retrieving and processing character data from the map API.

  This module follows the API Data Standardization principles:
  1. Single Source of Truth: Uses Character struct as the canonical representation
  2. Early Conversion: Converts API responses to Character structs immediately
  3. No Silent Renaming: Preserves field names consistently
  4. No Defensive Fallbacks: Handles errors explicitly
  5. Clear Contracts: Has explicit input/output contracts
  6. Explicit Error Handling: Fails fast with clear error messages
  7. Consistent Access Patterns: Uses the Access behavior for all struct access
  """
  require Logger
  alias WandererNotifier.Api.Http.Client
  alias WandererNotifier.Api.Map.UrlBuilder
  alias WandererNotifier.Data.Cache.Repository, as: CacheRepo
  alias WandererNotifier.Core.Config
  alias WandererNotifier.Core.Config.Timings
  alias WandererNotifier.Notifiers.Factory, as: NotifierFactory
  alias WandererNotifier.Data.Character

  @doc """
  Updates the tracked characters information in the cache.

  If cached_characters is provided, it will also identify and notify about new characters.

  ## Parameters
    - cached_characters: Optional list of cached characters for comparison

  ## Returns
    - {:ok, [Character.t()]} on success with a list of Character structs
    - {:error, {:json_parse_error, reason}} if JSON parsing fails
    - {:error, {:http_error, reason}} if HTTP request fails
    - {:error, {:domain_error, :map, reason}} for domain-specific errors
  """
  @spec update_tracked_characters([Character.t()] | nil) ::
          {:ok, [Character.t()]} | {:error, term()}
  def update_tracked_characters(cached_characters \\ nil) do
    Logger.debug("[CharactersClient] Starting update of tracked characters")

    with {:ok, _} <- check_characters_endpoint_availability(),
         {:ok, url} <- UrlBuilder.build_url("map/characters"),
         {:ok, body} <- fetch_characters_data(url) do
      handle_character_response(body, cached_characters)
    else
      {:error, {:http_error, _}} = error ->
        # HTTP errors already logged in fetch_characters_data
        error

      {:error, reason} = error ->
        if is_tuple(reason) and tuple_size(reason) == 3 and elem(reason, 0) == :domain_error do
          # Domain errors (like unavailable endpoint) already logged
          error
        else
          # Other errors (like URL building)
          Logger.error("[CharactersClient] Failed to update characters: #{inspect(reason)}")
          error
        end
    end
  end

  # Fetch character data from the API
  defp fetch_characters_data(url) do
    headers = UrlBuilder.get_auth_headers()

    case Client.get(url, headers) do
      {:ok, %{status_code: 200, body: body}} when is_binary(body) ->
        {:ok, body}

      {:ok, %{status_code: status_code}} ->
        Logger.error("[CharactersClient] API returned non-200 status: #{status_code}")
        {:error, {:http_error, status_code}}

      {:error, reason} ->
        Logger.error("[CharactersClient] HTTP request failed: #{inspect(reason)}")
        {:error, {:http_error, reason}}
    end
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
        # Extract characters data with fallbacks for different API formats
        characters_data =
          case parsed_json do
            %{"data" => data} when is_list(data) -> data
            %{"characters" => chars} when is_list(chars) -> chars
            data when is_list(data) -> data
            _ -> []
          end

        # Convert to Character structs with explicit validation
        Logger.debug(
          "[CharactersClient] Parsing #{length(characters_data)} characters from API response"
        )

        characters =
          Enum.map(characters_data, fn char_data ->
            try do
              Character.new(char_data)
            rescue
              e in ArgumentError ->
                Logger.warning("[CharactersClient] Failed to parse character: #{inspect(e)}")
                nil
            end
          end)
          |> Enum.reject(&is_nil/1)

        # Filter for tracked characters only
        tracked_characters = Enum.filter(characters, & &1.tracked)

        if tracked_characters == [] do
          Logger.warning("[CharactersClient] No tracked characters found in map API response")
        else
          Logger.debug(
            "[CharactersClient] Found #{length(tracked_characters)} tracked characters"
          )
        end

        # Cache the characters
        CacheRepo.set(
          "map:characters",
          tracked_characters,
          Timings.characters_cache_ttl()
        )

        # Find and notify about new characters
        _ = notify_new_tracked_characters(tracked_characters, cached_characters)

        {:ok, tracked_characters}

      {:error, reason} ->
        Logger.error("[CharactersClient] Failed to parse JSON: #{inspect(reason)}")

        Logger.debug(
          "[CharactersClient] Raw response body sample: #{String.slice(body, 0, 100)}..."
        )

        {:error, {:json_parse_error, reason}}
    end
  end

  @doc """
  Checks if the characters endpoint is available in the current map API.

  ## Returns
    - {:ok, true} if available
    - {:error, reason} if not available
  """
  @spec check_characters_endpoint_availability() :: {:ok, boolean()} | {:error, term()}
  def check_characters_endpoint_availability do
    Logger.debug("[CharactersClient] Checking characters endpoint availability")

    with {:ok, url} <- UrlBuilder.build_url("map/characters"),
         headers = UrlBuilder.get_auth_headers(),
         {:ok, response} <- Client.get(url, headers) do
      # We only need to verify that we get a successful response
      case response do
        %{status_code: status} when status >= 200 and status < 300 ->
          Logger.info("[CharactersClient] Characters endpoint is available")
          {:ok, true}

        %{status_code: status, body: body} ->
          error_reason = "Endpoint returned status #{status}: #{body}"
          Logger.warning("[CharactersClient] Characters endpoint returned error: #{error_reason}")
          {:error, error_reason}
      end
    else
      {:error, reason} ->
        Logger.warning(
          "[CharactersClient] Characters endpoint is NOT available: #{inspect(reason)}"
        )

        {:error, reason}
    end
  end

  @doc """
  Retrieves character activity data from the map API.

  ## Parameters
    - slug: Optional map slug override

  ## Returns
    - {:ok, activity_data} on success
    - {:error, {:json_parse_error, reason}} if JSON parsing fails
    - {:error, {error_type, {:http_error, reason}}} if HTTP request fails
    - {:error, {:unexpected_error, message}} for unexpected errors
  """
  @spec get_character_activity(String.t() | nil) :: {:ok, list(map())} | {:error, term()}
  def get_character_activity(slug \\ nil) do
    try do
      with {:ok, url} <- build_activity_url(slug),
           {:ok, response} <- fetch_activity_data(url),
           {:ok, activity_data} <- parse_activity_data(response) do
        {:ok, activity_data}
      else
        error -> error
      end
    rescue
      e -> handle_unexpected_activity_error(e)
    end
  end

  # Build URL for character activity endpoint
  defp build_activity_url(slug) do
    case UrlBuilder.build_url("map/character-activity", %{days: 1}, slug) do
      {:ok, url} ->
        {:ok, url}

      {:error, reason} ->
        Logger.error("[CharactersClient] Failed to build URL or headers: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # Fetch activity data from API
  defp fetch_activity_data(url) do
    headers = UrlBuilder.get_auth_headers()

    case Client.get(url, headers) do
      {:ok, %{status_code: 200, body: body}} when is_binary(body) ->
        {:ok, body}

      {:ok, %{status_code: status_code}} ->
        Logger.error("[CharactersClient] API returned non-200 status: #{status_code}")
        # Determine if this error is retryable
        error_type = if status_code >= 500, do: :retriable, else: :permanent
        {:error, {error_type, {:http_error, status_code}}}

      {:error, reason} ->
        Logger.error("[CharactersClient] HTTP request failed: #{inspect(reason)}")
        # Network errors are generally retryable
        {:error, {:retriable, {:http_error, reason}}}
    end
  end

  # Parse activity data from response body
  defp parse_activity_data(body) do
    case Jason.decode(body) do
      {:ok, parsed_json} ->
        # Extract and format activity data
        activity_data = extract_activity_data(parsed_json)

        Logger.debug(
          "[CharactersClient] Parsed #{length(activity_data)} activity entries from API response"
        )

        {:ok, activity_data}

      {:error, reason} ->
        log_json_parse_error(body, reason)
        {:error, {:json_parse_error, reason}}
    end
  end

  # Extract activity data from parsed JSON with fallbacks for different formats
  defp extract_activity_data(parsed_json) do
    case parsed_json do
      %{"data" => data} when is_list(data) -> data
      %{"activity" => activity} when is_list(activity) -> activity
      data when is_list(data) -> data
      _ -> []
    end
  end

  # Log JSON parse error with sample of body
  defp log_json_parse_error(body, reason) do
    Logger.error("[CharactersClient] Failed to parse JSON: #{inspect(reason)}")

    Logger.debug("[CharactersClient] Raw response body sample: #{String.slice(body, 0, 100)}...")
  end

  # Handle unexpected errors during character activity fetch
  defp handle_unexpected_activity_error(error) do
    error_message = "Error fetching character activity: #{inspect(error)}"
    Logger.error(error_message)
    {:error, {:unexpected_error, error_message}}
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
    # Find characters by their eve_id that are in new but not in cached
    new_char_ids = MapSet.new(new_chars, & &1.eve_id)
    cached_char_ids = MapSet.new(cached_chars, & &1.eve_id)

    # Get the difference (characters in new but not in cached)
    new_ids = MapSet.difference(new_char_ids, cached_char_ids)

    # Return the full character structs for new characters
    Enum.filter(new_chars, fn char -> MapSet.member?(new_ids, char.eve_id) end)
  end

  # Send notifications for each new character
  # No new characters
  defp notify_characters([]), do: {:ok, []}

  defp notify_characters(added_characters) do
    Logger.info("[CharactersClient] Found #{length(added_characters)} new tracked characters")

    Enum.each(added_characters, &send_character_notification_safely/1)

    {:ok, added_characters}
  end

  # Safely send a notification for a character, handling errors
  defp send_character_notification_safely(character) do
    try do
      send_character_notification(character)
    rescue
      e ->
        Logger.error(
          "[CharactersClient] Failed to send notification for new character: #{inspect(e)}"
        )
    end
  end

  @doc """
  Sends a notification for a new tracked character.
  """
  def send_character_notification(character_data) when is_map(character_data) do
    Logger.info("[CharactersClient] Sending notification for new tracked character")
    Logger.debug("[CharactersClient] Character data: #{inspect(character_data)}")

    # Convert to Character struct if not already
    character =
      if is_struct(character_data, WandererNotifier.Data.Character) do
        character_data
      else
        WandererNotifier.Data.Character.new(character_data)
      end

    # Create a generic notification that can be converted to various formats
    generic_notification =
      WandererNotifier.Notifiers.StructuredFormatter.format_character_notification(character)

    discord_format =
      WandererNotifier.Notifiers.StructuredFormatter.to_discord_format(generic_notification)

    # Send notification via factory
    NotifierFactory.notify(:send_discord_embed, [discord_format, :character_tracking])
  end
end
