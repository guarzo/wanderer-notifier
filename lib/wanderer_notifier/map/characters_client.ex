defmodule WandererNotifier.Map.CharactersClient do
  @moduledoc """
  Client for retrieving and processing character data from the map API.
  """

  alias WandererNotifier.HttpClient.Httpoison, as: HttpClient
  alias WandererNotifier.Cache.Keys, as: CacheKeys
  alias WandererNotifier.Cache.Repository, as: CacheRepo
  alias WandererNotifier.Character.Character
  alias WandererNotifier.Logger.Logger, as: AppLogger
  alias WandererNotifier.Config.Cache
  alias WandererNotifier.Config.Config
  alias WandererNotifier.Notifiers.StructuredFormatter
  alias WandererNotifier.Notifications.Factory, as: NotifierFactory

  @doc """
  Updates tracked character information from the map API.

  ## Parameters
    - cached_characters: List of cached characters for comparison

  ## Returns
    - {:ok, characters} on success
    - {:error, reason} on failure
  """
  def update_tracked_characters(cached_characters) do
    base_url = Config.get_api_base_url()
    url = "#{base_url}/map/characters"
    headers = get_auth_headers()

    case HttpClient.get(url, headers) do
      {:ok, %{status: 200, body: body}} ->
        handle_character_response(body, cached_characters)

      {:ok, %{status: status}} ->
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
    base_url = Config.get_api_base_url()
    params = URI.encode_query(%{"days" => days, "slug" => slug})
    url = "#{base_url}/map/character-activity?#{params}"
    headers = get_auth_headers()

    case HttpClient.get(url, headers) do
      {:ok, %{status: 200, body: body}} ->
        case Jason.decode(body) do
          {:ok, data} -> {:ok, data}
          {:error, reason} -> {:error, {:json_parse_error, reason}}
        end

      {:ok, %{status: status}} ->
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

  # Private helper functions

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

  defp extract_characters_data(parsed_json) do
    case parsed_json do
      %{"data" => data} when is_list(data) -> data
      %{"characters" => chars} when is_list(chars) -> chars
      data when is_list(data) -> data
      _ -> []
    end
  end

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

  defp standardize_character_data(raw_char_data) do
    cond do
      has_nested_eve_id?(raw_char_data) -> raw_char_data
      has_top_level_eve_id?(raw_char_data) -> raw_char_data
      has_only_character_id?(raw_char_data) -> handle_missing_eve_id(raw_char_data)
      is_map(raw_char_data) -> handle_missing_required_fields(raw_char_data)
      true -> handle_invalid_data_type(raw_char_data)
    end
  end

  defp has_nested_eve_id?(data) do
    is_map(data) &&
      Map.has_key?(data, "character") &&
      is_map(data["character"]) &&
      Map.has_key?(data["character"], "eve_id")
  end

  defp has_top_level_eve_id?(data) do
    is_map(data) && Map.has_key?(data, "eve_id")
  end

  defp has_only_character_id?(data) do
    is_map(data) && Map.has_key?(data, "character_id")
  end

  defp handle_missing_eve_id(data) do
    AppLogger.api_warn(
      "[CharactersClient] Character data has UUID character_id but no eve_id: #{inspect(data)}"
    )

    data
  end

  defp handle_missing_required_fields(data) do
    AppLogger.api_warn(
      "[CharactersClient] Character data missing required fields. " <>
        "Available keys: #{inspect(Map.keys(data))}"
    )

    AppLogger.api_debug("[CharactersClient] Raw character data: #{inspect(data)}")
    data
  end

  defp handle_invalid_data_type(data) do
    AppLogger.api_warn("[CharactersClient] Unexpected character data type: #{inspect(data)}")
    data
  end

  defp process_tracked_characters(tracked_characters, cached_characters) do
    # Cache the characters
    cache_ttl = Cache.characters_cache_ttl()
    CacheRepo.set(CacheKeys.character_list(), tracked_characters, cache_ttl)

    # Notify about new characters if we have cached data to compare against
    if cached_characters do
      notify_new_tracked_characters(tracked_characters, cached_characters)
    end
  end

  defp notify_new_tracked_characters(new_characters, cached_characters) do
    # Convert cached characters to a set of IDs for efficient lookup
    cached_ids = MapSet.new(cached_characters || [], & &1.id)

    # Find characters that aren't in the cached set
    new_characters
    |> Enum.reject(&(&1.id in cached_ids))
    |> Enum.each(&send_new_character_notification/1)
  end

  defp send_new_character_notification(character) do
    WandererNotifier.Notifiers.Discord.Notifier.send_new_tracked_character_notification(character)
  end

  defp get_auth_headers do
    api_key = Config.get_api_key()
    [{"Authorization", "Bearer #{api_key}"}]
  end
end
