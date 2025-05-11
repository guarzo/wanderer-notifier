defmodule WandererNotifier.Map.Clients.CharactersClient do
  @moduledoc """
  curl -X 'GET' \
  'https://<map url>/api/map/user_characters?slug=<map slug>' \
  -H 'accept: application/json' \
  -H 'Authorization: Bearer <token>' \
    Client for retrieving and processing character data from the map API.
  {
  "data": [
    {
      "characters": [
        {
          "name": "Shiv Black",
          "corporation_id": 98801377,
          "alliance_id": null,
          "alliance_ticker": null,
          "corporation_ticker": "SAL.T",
          "eve_id": "2118083819"
        },
        {
          "name": "ScreamKream",
          "corporation_id": 1000045,
          "alliance_id": null,
          "alliance_ticker": null,
          "corporation_ticker": "STI",
          "eve_id": "2123019019"
        },
        {
          "name": "Shiv Dark",
          "corporation_id": 98801377,
          "alliance_id": null,
          "alliance_ticker": null,
          "corporation_ticker": "SAL.T",
          "eve_id": "2117775277"
        },
        {
          "name": "Shivon",
          "corporation_id": 98648442,
          "alliance_id": 99010452,
          "alliance_ticker": "STILR",
          "corporation_ticker": "FLYGD",
          "eve_id": "2117608364"
        },
        {
          "name": "Huffypuff",
          "corporation_id": 98801377,
          "alliance_id": null,
          "alliance_ticker": null,
          "corporation_ticker": "SAL.T",
          "eve_id": "2123019111"
        },
        {
          "name": "Nimby Karen",
          "corporation_id": 98801377,
          "alliance_id": null,
          "alliance_ticker": null,
          "corporation_ticker": "SAL.T",
          "eve_id": "2123019188"
        }
      ],
      "main_character_eve_id": "2117608364"
    },
    {
      "characters": [
        {
          "name": "Ivan Ego",
          "corporation_id": 98757447,
          "alliance_id": null,
          "alliance_ticker": null,
          "corporation_ticker": "0MARR",
          "eve_id": "2118274823"
        },
        {
          "name": "Norrek Magma",
          "corporation_id": 98757447,
          "alliance_id": null,
          "alliance_ticker": null,
          "corporation_ticker": "0MARR",
          "eve_id": "2119173826"
        },
        {
          "name": "Norfane",
          "corporation_id": 98648442,
          "alliance_id": 99010452,
          "alliance_ticker": "STILR",
          "corporation_ticker": "FLYGD",
          "eve_id": "629507683"
        }
      ],
      "main_character_eve_id": null
    }
  ]
  }
  """

  alias WandererNotifier.HttpClient.Httpoison, as: HttpClient
  alias WandererNotifier.Cache.Keys, as: CacheKeys
  alias WandererNotifier.Cache.CachexImpl, as: CacheRepo
  alias WandererNotifier.Logger.Logger, as: AppLogger
  alias WandererNotifier.Config

  @doc """
  Updates tracked character information from the map API.

  ## Parameters
    - cached_characters: List of cached characters for comparison

  ## Returns
    - {:ok, characters} on success
    - {:error, reason} on failure
  """
  def update_tracked_characters(cached_characters) do
    base_url = Config.base_map_url()
    slug = Config.map_slug()
    url = "#{base_url}/api/map/user_characters?slug=#{slug}"
    headers = get_auth_headers()

    AppLogger.api_debug("[CharactersClient] Fetching characters",
      url: url,
      slug: slug,
      base_url: base_url
    )

    case HttpClient.get(url, headers) do
      {:ok, %{status_code: 200, body: body}} ->
        handle_character_response(body, cached_characters)

      {:ok, %{status_code: 500, body: body}} ->
        # Server error - fall back to cache if available
        AppLogger.api_error(
          "⚠️ Server error (500) when fetching characters - falling back to cache",
          url: url,
          body: inspect(body)
        )

        if cached_characters && length(cached_characters) > 0 do
          # Use existing cached data to avoid disruption
          AppLogger.api_info(
            "Using #{length(cached_characters)} cached characters after server error"
          )

          {:ok, cached_characters}
        else
          {:error, {:http_error, %{body: body || "Server error", status_code: 500}}}
        end

      {:ok, %{status_code: status, body: body}} ->
        AppLogger.api_error("⚠️ Failed to fetch characters",
          status: status,
          body: inspect(body),
          url: url
        )

        if cached_characters && length(cached_characters) > 0 do
          # Use existing cached data for non-critical error
          AppLogger.api_info(
            "Using #{length(cached_characters)} cached characters after HTTP error"
          )

          {:ok, cached_characters}
        else
          {:error, {:http_error, %{body: body, status_code: status}}}
        end

      {:error, reason} ->
        AppLogger.api_error("⚠️ Failed to fetch characters",
          error: inspect(reason),
          url: url
        )

        if cached_characters && length(cached_characters) > 0 do
          # Use existing cached data for connection error
          AppLogger.api_info(
            "Using #{length(cached_characters)} cached characters after connection error"
          )

          {:ok, cached_characters}
        else
          {:error, {:http_error, reason}}
        end
    end
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
    base_url = Config.base_map_url()
    url = build_activity_url(base_url, slug, days)
    headers = get_auth_headers()

    AppLogger.api_debug("[CharactersClient] Fetching character activity", url: url, days: days)

    case HttpClient.get(url, headers) do
      {:ok, %{status_code: 200, body: body}} ->
        handle_activity_response(body)

      {:ok, %{status_code: status, body: body}} ->
        AppLogger.api_error("⚠️ Failed to fetch character activity",
          status: status,
          url: url,
          body: inspect(body)
        )

        {:error, {:http_error, status}}

      {:error, reason} ->
        AppLogger.api_error("⚠️ Failed to fetch character activity",
          error: inspect(reason),
          url: url
        )

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
    AppLogger.api_debug("[CharactersClient] Processing character response",
      preview: String.slice(body, 0, 100) <> "... (truncated)"
    )

    case Jason.decode(body) do
      {:ok, data} ->
        process_tracked_characters(data, cached_characters)

      {:error, error} ->
        AppLogger.api_error("[CharactersClient] Failed to decode JSON response",
          error: inspect(error)
        )

        # Use cached data if JSON parsing fails but we have cached characters
        if cached_characters && length(cached_characters) > 0 do
          AppLogger.api_info(
            "Using #{length(cached_characters)} cached characters after JSON decode error"
          )

          {:ok, cached_characters}
        else
          {:error, {:json_decode_error, error}}
        end
    end
  end

  def handle_character_response(body, cached_characters) when is_map(body) do
    process_tracked_characters(body, cached_characters)
  end

  def handle_activity_response(body) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, data} -> {:ok, data}
      {:error, error} -> {:error, {:json_decode_error, error}}
    end
  end

  def handle_activity_response(body) when is_map(body), do: {:ok, body}

  # Private helper functions

  # Safely access the cache repository
  defp safe_cache_repo_call(func, args, default) do
    try do
      apply(CacheRepo, func, args)
    rescue
      e ->
        # Log this only once per minute to avoid log spam
        cache_error_key = "#{func}_error_logged"
        last_logged = Process.get(cache_error_key)
        now = System.monotonic_time(:second)

        if is_nil(last_logged) || now - last_logged > 60 do
          AppLogger.api_error("Cache operation failed",
            function: func,
            args: inspect(args),
            error: Exception.message(e)
          )

          Process.put(cache_error_key, now)
        end

        default
    end
  end

  defp process_tracked_characters(tracked_characters, cached_characters) do
    # Extract characters from the new nested structure
    character_list = extract_characters_from_response(tracked_characters)

    # Only cache if we have valid data
    if character_list && is_list(character_list) && length(character_list) > 0 do
      # Cache the characters
      cache_ttl = Config.characters_cache_ttl()

      safe_cache_repo_call(
        :set,
        [CacheKeys.character_list(), character_list, cache_ttl],
        {:error, :cache_error}
      )

      # Log character count
      AppLogger.api_info("[CharactersClient] Cached #{length(character_list)} characters")
    end

    # Notify about new characters if we have cached data to compare against
    if cached_characters && cached_characters != [] && character_list != [] do
      notify_new_tracked_characters(character_list, cached_characters)
    else
      AppLogger.debug(
        "[CharactersClient] Skipping notifications: no cached_characters prior to API call or empty result"
      )
    end

    {:ok, character_list}
  end

  # Extract characters from the new nested format
  defp extract_characters_from_response(response) do
    cond do
      # New format: data is an array of character groups
      is_map(response) && Map.has_key?(response, "data") && is_list(response["data"]) ->
        response["data"]
        |> Enum.filter(fn group ->
          Map.has_key?(group, "characters") && is_list(group["characters"])
        end)
        |> Enum.flat_map(fn group ->
          # Enhance each character with main_character_eve_id from the group
          main_id = Map.get(group, "main_character_eve_id")

          Enum.map(group["characters"], fn char ->
            # Add is_main field to the character
            is_main =
              if is_nil(main_id) do
                # No main defined for this group
                false
              else
                char["eve_id"] == main_id
              end

            # Add proper tracking flag for compatibility
            Map.merge(char, %{
              "tracked" => true,
              "is_main" => is_main,
              # For compatibility with old format
              "character_id" => char["eve_id"]
            })
          end)
        end)

      # Direct list of character groups
      is_list(response) ->
        response
        |> Enum.filter(fn group ->
          is_map(group) && Map.has_key?(group, "characters") && is_list(group["characters"])
        end)
        |> Enum.flat_map(fn group ->
          # Enhance each character with main_character_eve_id from the group
          main_id = Map.get(group, "main_character_eve_id")

          Enum.map(group["characters"], fn char ->
            # Add is_main field to the character
            is_main =
              if is_nil(main_id) do
                # No main defined for this group
                false
              else
                char["eve_id"] == main_id
              end

            # Add proper tracking flag for compatibility
            Map.merge(char, %{
              "tracked" => true,
              "is_main" => is_main,
              # For compatibility with old format
              "character_id" => char["eve_id"]
            })
          end)
        end)

      # Fallback for unexpected formats
      true ->
        AppLogger.api_error(
          "[CharactersClient] Expected response with 'data' field containing character groups, got: #{inspect(response, limit: 500)}"
        )

        []
    end
  end

  defp notify_new_tracked_characters(new_characters, cached_characters) do
    # Convert cached characters to a set of EVE IDs for efficient lookup
    cached_ids =
      MapSet.new(cached_characters || [], fn c ->
        case c do
          %{"character" => %{"eve_id" => eve_id}} -> eve_id
          %{"eve_id" => eve_id} -> eve_id
          %{:character => %{eve_id: eve_id}} -> eve_id
          %{:eve_id => eve_id} -> eve_id
          _ -> nil
        end
      end)

    # Find characters that aren't in the cached set
    new_characters
    |> Enum.reject(fn c ->
      eve_id =
        case c do
          %{"character" => %{"eve_id" => id}} -> id
          %{"eve_id" => id} -> id
          %{:character => %{eve_id: id}} -> id
          %{:eve_id => id} -> id
          _ -> nil
        end

      eve_id in cached_ids
    end)
    |> Enum.each(&notify/1)
  end

  # Notify helper, similar to system notification flow
  defp notify(character_map) do
    character_struct = WandererNotifier.Map.MapCharacter.new(character_map)
    character_id = character_struct.character_id

    require Logger

    # Only send notification if determiner says we should
    if WandererNotifier.Notifications.Determiner.Character.should_notify?(
         character_id,
         character_struct
       ) do
      Logger.info(
        "[CharactersClient] Sending notification for new EVE character_id: #{inspect(character_id)} (name: #{character_struct.name})"
      )

      WandererNotifier.Notifications.Dispatcher.run(:send_new_tracked_character_notification, [
        character_struct
      ])
    else
      Logger.info(
        "[CharactersClient] Skipping notification for EVE character_id: #{inspect(character_id)} (name: #{character_struct.name}) - deduplication or feature flag"
      )
    end
  end

  defp get_auth_headers do
    api_key = Config.map_token()
    AppLogger.api_debug("[CharactersClient] Fetching characters", api_key: api_key)
    [{"Authorization", "Bearer #{api_key}"}]
  end

  defp build_activity_url(base_url, nil, days),
    do: "#{base_url}/map/characters/activity?days=#{days}"

  defp build_activity_url(base_url, slug, days),
    do: "#{base_url}/map/characters/#{slug}/activity?days=#{days}"
end
