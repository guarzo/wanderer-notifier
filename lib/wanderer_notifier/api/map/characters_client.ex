defmodule WandererNotifier.Api.Map.CharactersClient do
  @moduledoc """
  Client for retrieving and processing character data from the map API.
  Uses structured data types and consistent parsing to simplify the logic.
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
    - {:ok, characters} on success
    - {:error, reason} on failure
  """
  def update_tracked_characters(cached_characters \\ nil) do
    Logger.debug("[CharactersClient] Starting update of tracked characters")

    # First check if the characters endpoint is available
    case check_characters_endpoint_availability() do
      {:ok, _} ->
        # Endpoint is available, proceed with update
        with {:ok, url} <- UrlBuilder.build_url("map/characters"),
             headers = UrlBuilder.get_auth_headers() do
          
          # Make the API request directly to handle raw response
          case Client.get(url, headers) do
            {:ok, %{status_code: 200, body: body, headers: _headers}} when is_binary(body) ->
              # Successfully got response, now parse it carefully
              case Jason.decode(body) do
                {:ok, parsed_json} ->
                  # Extract characters data with fallbacks for different API formats
                  characters_data = case parsed_json do
                    %{"data" => data} when is_list(data) -> data
                    %{"characters" => chars} when is_list(chars) -> chars
                    data when is_list(data) -> data
                    _ -> []
                  end

                  # Convert to Character structs
                  Logger.debug("[CharactersClient] Parsing #{length(characters_data)} characters from API response")
                  characters = Enum.map(characters_data, &Character.new/1)

                  # Filter for tracked characters only
                  tracked_characters = Enum.filter(characters, & &1.tracked)

                  if tracked_characters == [] do
                    Logger.warning("[CharactersClient] No tracked characters found in map API response")
                  else
                    Logger.debug("[CharactersClient] Found #{length(tracked_characters)} tracked characters")
                  end

                  # Cache the characters
                  CacheRepo.set("map:characters", tracked_characters, Timings.characters_cache_ttl())

                  # Find and notify about new characters
                  _ = notify_new_tracked_characters(tracked_characters, cached_characters)

                  {:ok, tracked_characters}
                  
                {:error, reason} ->
                  Logger.error("[CharactersClient] Failed to parse JSON: #{inspect(reason)}")
                  Logger.debug("[CharactersClient] Raw response body sample: #{String.slice(body, 0, 100)}...")
                  {:error, {:json_parse_error, reason}}
              end
              
            {:ok, %{status_code: status_code}} when status_code != 200 ->
              Logger.error("[CharactersClient] API returned non-200 status: #{status_code}")
              {:error, {:http_error, status_code}}
              
            {:error, reason} ->
              Logger.error("[CharactersClient] HTTP request failed: #{inspect(reason)}")
              {:error, {:http_error, reason}}
          end
        else
          {:error, reason} ->
            Logger.error("[CharactersClient] Failed to build URL or headers: #{inspect(reason)}")
            {:error, reason}
        end

      {:error, reason} ->
        # Endpoint is not available, log detailed error
        Logger.error(
          "[CharactersClient] Characters endpoint is not available: #{inspect(reason)}"
        )

        Logger.error("[CharactersClient] This map API may not support character tracking")

        Logger.error(
          "[CharactersClient] To disable character tracking, set ENABLE_CHARACTER_TRACKING=false"
        )

        # Return a more descriptive error
        {:error, {:domain_error, :map, {:characters_endpoint_unavailable, reason}}}
    end
  end

  @doc """
  Checks if the characters endpoint is available in the current map API.

  ## Returns
    - {:ok, true} if available
    - {:error, reason} if not available
  """
  def check_characters_endpoint_availability do
    Logger.debug(
      "[CharactersClient] Checking characters endpoint availability"
    )

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
          Logger.warning(
            "[CharactersClient] Characters endpoint returned error: #{error_reason}"
          )
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
    - {:error, reason} on failure
  """
  def get_character_activity(slug \\ nil) do
    try do
      with {:ok, url} <- UrlBuilder.build_url("map/character-activity", %{}, slug),
           headers = UrlBuilder.get_auth_headers() do
           
        # Make the API request directly to handle raw response
        case Client.get(url, headers) do
          {:ok, %{status_code: 200, body: body, headers: _headers}} when is_binary(body) ->
            # Successfully got response, now parse it carefully
            case Jason.decode(body) do
              {:ok, parsed_json} ->
                # Extract activity data with fallbacks for different API formats
                activity_data = case parsed_json do
                  %{"data" => data} when is_list(data) -> data
                  %{"activity" => activity} when is_list(activity) -> activity
                  data when is_list(data) -> data
                  _ -> []
                end

                Logger.debug("[CharactersClient] Parsed #{length(activity_data)} activity entries from API response")

                # Return the validated activity data
                {:ok, activity_data}
                
              {:error, reason} ->
                Logger.error("[CharactersClient] Failed to parse JSON: #{inspect(reason)}")
                Logger.debug("[CharactersClient] Raw response body sample: #{String.slice(body, 0, 100)}...")
                {:error, {:json_parse_error, reason}}
            end
            
          {:ok, %{status_code: status_code}} when status_code != 200 ->
            Logger.error("[CharactersClient] API returned non-200 status: #{status_code}")
            # Determine if this error is retryable
            error_type = if status_code >= 500, do: :retriable, else: :permanent
            {:error, {error_type, {:http_error, status_code}}}
            
          {:error, reason} ->
            Logger.error("[CharactersClient] HTTP request failed: #{inspect(reason)}")
            # Network errors are generally retryable
            {:error, {:retriable, {:http_error, reason}}}
        end
      else
        {:error, reason} ->
          Logger.error("[CharactersClient] Failed to build URL or headers: #{inspect(reason)}")
          {:error, reason}
      end
    rescue
      e ->
        error_message = "Error fetching character activity: #{inspect(e)}"
        Logger.error(error_message)
        {:error, {:unexpected_error, error_message}}
    end
  end

  @doc """
  Identifies new tracked characters and sends notifications.

  ## Parameters
    - new_characters: List of newly fetched tracked characters
    - cached_characters: List of previously cached characters

  ## Returns
    - {:ok, new_characters} always to maintain consistent return value
  """
  def notify_new_tracked_characters(new_characters, cached_characters) do
    if Config.character_tracking_enabled?() && Config.character_notifications_enabled?() do
      # Check if we have both new and cached characters
      new_chars = new_characters || []
      cached_chars = cached_characters || []

      # Find characters that are in new_chars but not in cached_chars
      added_characters =
        if cached_chars == [] do
          # If there are no cached characters, this might be the first run
          # In that case, don't notify about all characters to avoid spamming
          []
        else
          new_chars
          |> Enum.filter(fn char ->
            !Enum.any?(cached_chars, fn c ->
              char.eve_id == c.eve_id
            end)
          end)
        end

      Enum.each(added_characters, fn char ->
        Task.start(fn ->
          try do
            # Create the character notification data structure
            character_info = %{
              "character_id" => char.eve_id,
              "character_name" => char.name,
              "corporation_name" => char.corporation_ticker
            }

            send_character_notification(character_info)

            Logger.info("[CharactersClient] New tracked character: #{char.name}")
          rescue
            e ->
              Logger.error(
                "[CharactersClient] Error sending character notification: #{inspect(e)}"
              )
          end
        end)
      end)

      if added_characters != [] do
        Logger.info("[CharactersClient] Found #{length(added_characters)} new tracked characters")
      end
    else
      Logger.debug("[CharactersClient] Character notifications disabled")
    end

    {:ok, new_characters}
  end

  # Helper function to send character notifications
  defp send_character_notification(character_info) do
    notifier = NotifierFactory.get_notifier()
    notifier.send_new_tracked_character_notification(character_info)
  end
end
