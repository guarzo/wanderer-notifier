defmodule WandererNotifier.Map.Clients.CharactersClient do
  @moduledoc """
    Client for retrieving and processing character data from the map API.
    {
    "data": [
      {
        "id": "4712b7b0-37a0-42a6-91ba-1a5bf747d1a0",
        "character": {
          "name": "Nimby Karen",
          "alliance_id": null,
          "alliance_ticker": null,
          "corporation_id": 98801377,
          "corporation_ticker": "SAL.T",
          "eve_id": "2123019188"
        },
        "inserted_at": "2025-01-01T03:32:51.041452Z",
        "updated_at": "2025-01-01T03:32:51.044408Z",
        "tracked": true,
        "character_id": "90ff63d4-28f3-4071-8717-da1d0d39990e",
        "map_id": "678c43cf-f71f-4e14-932d-0545465cdff0"
      },
      {
        "id": "0962d53a-4419-4f3c-80f5-fac41e618181",
        "character": {
          "name": "Dismas November",
          "alliance_id": null,
          "alliance_ticker": null,
          "corporation_id": 98434706,
          "corporation_ticker": "DISHL",
          "eve_id": "2120970663"
        },
        "inserted_at": "2025-01-01T01:59:31.031640Z",
        "updated_at": "2025-01-01T01:59:31.031640Z",
        "tracked": true,
        "character_id": "e630f39f-8027-4963-a522-ebe1bb45a3b5",
        "map_id": "678c43cf-f71f-4e14-932d-0545465cdff0"
      },
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
    url = "#{base_url}/api/map/characters?slug=#{Config.map_slug()}"
    headers = get_auth_headers()

    AppLogger.api_debug("[CharactersClient] Fetching characters", url: url, headers: headers)

    case HttpClient.get(url, headers) do
      {:ok, %{status_code: 200, body: body}} ->
        handle_character_response(body, cached_characters)

      {:ok, %{status_code: status}} ->
        AppLogger.api_error("⚠️ Failed to fetch characters", status: status)
        {:error, {:http_error, status}}

      {:error, reason} ->
        AppLogger.api_error("⚠️ Failed to fetch characters", error: inspect(reason))
        {:error, {:http_error, reason}}
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

    case HttpClient.get(url, headers) do
      {:ok, %{status_code: 200, body: body}} ->
        handle_activity_response(body)

      {:ok, %{status_code: status}} ->
        AppLogger.api_error("⚠️ Failed to fetch character activity", status: status)
        {:error, {:http_error, status}}

      {:error, reason} ->
        AppLogger.api_error("⚠️ Failed to fetch character activity", error: inspect(reason))
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
      {:ok, data} -> process_tracked_characters(data, cached_characters)
      {:error, error} -> {:error, {:json_decode_error, error}}
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

  defp process_tracked_characters(tracked_characters, cached_characters) do
    if !(is_map(tracked_characters) and Map.has_key?(tracked_characters, "data")) do
      raise ArgumentError,
            "Expected tracked_characters to be a map with a 'data' field, got: #{inspect(tracked_characters)}"
    end

    character_list = Map.get(tracked_characters, "data")

    # Cache the characters
    cache_ttl = Config.characters_cache_ttl()
    CacheRepo.set(CacheKeys.character_list(), character_list, cache_ttl)

    # Notify about new characters if we have cached data to compare against
    if cached_characters do
      notify_new_tracked_characters(character_list, cached_characters)
    end

    {:ok, character_list}
  end

  defp notify_new_tracked_characters(new_characters, cached_characters) do
    # Convert cached characters to a set of EVE IDs for efficient lookup
    cached_ids =
      MapSet.new(cached_characters || [], fn c ->
        case c do
          %{"character" => %{"eve_id" => eve_id}} -> eve_id
          %{:character => %{eve_id: eve_id}} -> eve_id
          _ -> nil
        end
      end)

    # Find characters that aren't in the cached set
    new_characters
    |> Enum.reject(fn c ->
      eve_id =
        case c do
          %{"character" => %{"eve_id" => id}} -> id
          %{:character => %{eve_id: id}} -> id
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
    Logger.info("[CharactersClient] Notifying for EVE character_id: #{inspect(character_id)} (struct: #{inspect(character_struct)})")

    # Only send notification if determiner says we should
    if WandererNotifier.Notifications.Determiner.Character.should_notify?(character_id, character_struct) do
      Logger.info("[CharactersClient] Sending notification for new EVE character_id: #{inspect(character_id)} (name: #{character_struct.name})")
      WandererNotifier.Notifiers.Discord.Notifier.send_new_tracked_character_notification(character_struct)
    else
      Logger.info("[CharactersClient] Skipping notification for EVE character_id: #{inspect(character_id)} (name: #{character_struct.name}) - deduplication or feature flag")
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
