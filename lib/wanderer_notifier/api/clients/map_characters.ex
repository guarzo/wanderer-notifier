defmodule WandererNotifier.Api.Clients.MapCharacters do
  @moduledoc """
  Client for interacting with character-related map API endpoints
  """

  alias WandererNotifier.HttpClient.Behaviour, as: HttpClient
  alias WandererNotifier.HttpClient.Httpoison
  alias WandererNotifier.Config.Config
  alias WandererNotifier.Cache.Helpers, as: CacheHelpers
  alias WandererNotifier.Cache.Keys, as: CacheKeys
  alias WandererNotifier.Cache.Repository, as: CacheRepo
  alias WandererNotifier.Character.Character
  alias WandererNotifier.Logger.Logger, as: AppLogger
  alias WandererNotifier.Notifications.Determiner.Character, as: CharacterDeterminer
  alias WandererNotifier.Notifications.Interface, as: NotificationInterface

  @doc """
  Updates the list of tracked characters.

  ## Parameters
    - cached_characters: Optional list of already cached characters

  ## Returns
    - {:ok, characters} on success
    - {:error, reason} on failure
  """
  def update_tracked_characters(cached_characters \\ nil) do
    AppLogger.api_debug("Starting update of tracked characters")

    # If already provided with processed characters, use them directly
    if is_list(cached_characters) && length(cached_characters) > 0 do
      sample = Enum.at(cached_characters, 0)

      AppLogger.api_info(
        "Using provided character list of #{length(cached_characters)} items. Sample: #{inspect(sample, limit: 200)}"
      )

      update_cache(cached_characters, nil)
      {:ok, cached_characters}
    else
      # Otherwise fetch from API
      with {:ok, chars_url} <- build_characters_url(),
           _ <- AppLogger.api_debug("Characters URL built", url: chars_url),
           {:ok, body} <- fetch_characters_body(chars_url),
           _ <-
             AppLogger.api_debug("Received response body",
               body_preview: String.slice(body, 0, 100)
             ),
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
  end

  @doc """
  Updates tracked characters using a raw API response body.

  ## Parameters
    - raw_body: The raw API response body as string
    - cached_characters: Optional list of cached characters for comparison

  ## Returns
    - {:ok, characters} on success
    - {:error, reason} on failure
  """
  def update_tracked_characters(raw_body, cached_characters) when is_binary(raw_body) do
    AppLogger.api_debug(
      "Processing raw API response body",
      body_preview: String.slice(raw_body, 0, 150)
    )

    case parse_characters_response(raw_body) do
      {:ok, parsed_chars} ->
        update_cache(parsed_chars, cached_characters)
        notify_new_tracked_characters(parsed_chars, cached_characters)
        {:ok, parsed_chars}

      {:error, reason} ->
        AppLogger.api_error("Failed to parse character response body", error: inspect(reason))
        {:error, reason}
    end
  end

  @doc """
  Checks if the characters endpoint is available.

  ## Returns
    - {:ok, true} if available
    - {:error, reason} if not available
  """
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

  # Private helper functions

  defp build_characters_url do
    base_url_with_slug = Config.map_url()
    map_token = Config.map_token()

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
    uri = URI.parse(base_url_with_slug)
    slug_id = extract_slug_id(uri)
    base_host = get_base_host(uri)
    url = build_final_url(base_host, slug_id)

    AppLogger.api_debug("Final URL constructed", url: url)
    {:ok, url}
  end

  defp extract_slug_id(uri) do
    path = uri.path || ""
    path = String.trim_trailing(path, "/")

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

    headers = [
      {"Authorization", "Bearer #{map_token}"},
      {"Content-Type", "application/json"},
      {"Accept", "application/json"}
    ]

    AppLogger.api_debug("Requesting characters data", url: chars_url)

    case Httpoison.get(chars_url, headers) do
      {:ok, %{status_code: status_code, body: body}} when status_code in 200..299 ->
        AppLogger.api_debug("Characters request successful", status: status_code)
        {:ok, body}

      {:ok, %{status_code: status_code, body: body}} ->
        AppLogger.api_error("Characters request failed", status: status_code, body: body)
        {:error, "Failed to fetch characters, status: #{status_code}"}

      {:error, reason} ->
        AppLogger.api_error("Characters request error", error: inspect(reason))
        {:error, reason}
    end
  end

  defp parse_characters_response(body) do
    case Jason.decode(body) do
      {:ok, decoded} when is_map(decoded) ->
        parse_response_content(decoded)

      {:ok, _} ->
        AppLogger.api_error("Unexpected response format, not a JSON object")
        {:error, "Unexpected response format, not a JSON object"}

      {:error, reason} ->
        AppLogger.api_error("Failed to decode JSON response", error: inspect(reason))
        {:error, reason}
    end
  end

  defp parse_response_content(decoded) do
    characters = decoded["characters"] || []

    if is_list(characters) do
      transformed_chars = transform_characters(characters)
      AppLogger.api_info("Parsed #{length(transformed_chars)} tracked characters")
      {:ok, transformed_chars}
    else
      AppLogger.api_error("Invalid characters format, expected array")
      {:error, "Invalid characters format, expected array"}
    end
  end

  defp transform_characters(characters) do
    Enum.map(characters, &Character.from_map/1)
  end

  defp update_cache(new_characters, _old_characters) do
    CacheRepo.put(CacheKeys.character_list(), new_characters)
    {:ok, new_characters}
  end

  defp notify_new_tracked_characters(new_characters, nil) do
    # If no cached characters provided, assume all are new for initial load
    AppLogger.api_info("No cached characters provided, skipping new character notifications")
    {:ok, :no_cached_characters}
  end

  defp notify_new_tracked_characters(new_characters, old_characters)
       when is_list(old_characters) do
    # Find characters in new list that weren't in the old list
    CharacterDeterminer.detect_new_tracked_characters(new_characters, old_characters)
    |> Enum.each(fn character ->
      NotificationInterface.send_notification(:new_tracked_character, %{character: character})
    end)

    {:ok, :notified}
  end

  defp typeof(x) do
    cond do
      is_nil(x) -> "nil"
      is_binary(x) -> "binary"
      is_boolean(x) -> "boolean"
      is_function(x) -> "function"
      is_list(x) -> "list"
      is_map(x) -> "map"
      is_number(x) -> "number"
      is_tuple(x) -> "tuple"
      is_pid(x) -> "pid"
      is_port(x) -> "port"
      is_reference(x) -> "reference"
      is_atom(x) -> "atom"
      true -> "unknown"
    end
  end
end
