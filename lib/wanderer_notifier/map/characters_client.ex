defmodule WandererNotifier.Map.CharactersClient do
  @moduledoc """
  Client for retrieving and processing character data from the map API.
  """

  alias WandererNotifier.HttpClient.Httpoison, as: HttpClient
  alias WandererNotifier.HttpClient.UrlBuilder
  alias WandererNotifier.HttpClient.ErrorHandler
  alias WandererNotifier.Cache.Keys, as: CacheKeys
  alias WandererNotifier.Cache.Repository, as: CacheRepo
  alias WandererNotifier.Character.Character
  alias WandererNotifier.Logger.Logger, as: AppLogger
  alias WandererNotifier.Config.Cache

  @doc """
  Updates tracked character information from the map API.

  ## Parameters
    - cached_characters: List of cached characters for comparison

  ## Returns
    - {:ok, characters} on success
    - {:error, reason} on failure
  """
  def update_tracked_characters(cached_characters) do
    case UrlBuilder.build_url("map/characters") do
      {:ok, url} ->
        headers = UrlBuilder.get_auth_headers()

        case HttpClient.get(url, headers) do
          {:ok, response} ->
            process_characters_response(response, cached_characters)

          {:error, reason} ->
            AppLogger.api_error("⚠️ Failed to fetch characters", error: inspect(reason))
            {:error, {:http_error, reason}}
        end

      {:error, reason} ->
        AppLogger.api_error("⚠️ Failed to build URL", error: inspect(reason))
        {:error, reason}
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
    params = %{
      "days" => days,
      "slug" => slug
    }

    case UrlBuilder.build_url("map/character-activity", params) do
      {:ok, url} ->
        headers = UrlBuilder.get_auth_headers()

        case HttpClient.get(url, headers) do
          {:ok, response} ->
            process_activity_response(response)

          {:error, reason} ->
            AppLogger.api_error("⚠️ Failed to fetch character activity", error: inspect(reason))
            {:error, {:http_error, reason}}
        end

      {:error, reason} ->
        AppLogger.api_error("⚠️ Failed to build URL", error: inspect(reason))
        {:error, reason}
    end
  end

  # Private helper functions

  defp process_characters_response(response, cached_characters) do
    case ErrorHandler.handle_http_response(response, domain: :map, tag: "CharactersClient") do
      {:ok, parsed_response} ->
        process_and_cache_characters(parsed_response, cached_characters)

      {:error, reason} ->
        AppLogger.api_error("Failed to process characters response", error: inspect(reason))
        {:error, reason}
    end
  end

  defp process_activity_response(response) do
    case ErrorHandler.handle_http_response(response, domain: :map, tag: "CharacterActivity") do
      {:ok, parsed_response} ->
        {:ok, parsed_response}

      {:error, reason} ->
        AppLogger.api_error("Failed to process activity response", error: inspect(reason))
        {:error, reason}
    end
  end

  defp process_and_cache_characters(response, cached_characters) do
    characters =
      response
      |> Enum.map(&Character.from_map/1)
      |> Enum.reject(&is_nil/1)

    # Cache the characters with TTL
    cache_ttl = Cache.characters_cache_ttl()
    CacheRepo.set(CacheKeys.character_list(), characters, cache_ttl)

    # Notify about new characters if we have cached data to compare against
    if cached_characters do
      notify_new_tracked_characters(characters, cached_characters)
    end

    {:ok, characters}
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
end
