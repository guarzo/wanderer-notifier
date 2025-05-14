defmodule WandererNotifier.Map.Clients.CharactersClient do
  @moduledoc """
  Client for retrieving and processing character data from the map API.
  """

  alias WandererNotifier.HttpClient.Httpoison, as: HttpClient
  alias WandererNotifier.{Config, Cache}
  alias Cache.{Keys, CachexImpl}
  alias WandererNotifier.Logger.Logger
  alias WandererNotifier.Map.MapCharacter
  alias WandererNotifier.Notifications.Determiner.Character, as: CharDeterminer
  alias WandererNotifier.Notifications.Dispatcher

  @type reason :: term()
  @type character :: map()
  @type update_result :: {:ok, [character()]} | {:error, reason()}

  @doc """
  Fetches user characters from the map API, processes and caches them,
  and notifies about any genuinely new characters.

  Options:
    - `suppress_notifications`: When set to `true`, no notifications will be sent (default: `false`)

  Returns:
    - `{:ok, characters}` on success (whether new or cached)
    - `{:error, reason}` on total failure
  """
  @spec update_tracked_characters([character()], Keyword.t()) :: update_result()
  def update_tracked_characters(cached \\ [], opts \\ []) do
    url = characters_url()
    headers = auth_header()

    result =
      with {:ok, %{status_code: 200, body: body}} <- HttpClient.get(url, headers),
           {:ok, decoded} <- decode_body(body),
           chars when is_list(chars) <- extract_characters(decoded) do
        Logger.api_debug("API responded with #{length(chars)} characters")
        process_and_cache(chars, cached, opts)
      else
        {:ok, %{status_code: status, body: body}} ->
          error_preview = if is_binary(body), do: String.slice(body, 0, 100), else: inspect(body)

          Logger.api_error("Character API HTTP error",
            status: status,
            body_preview: error_preview
          )

          {:error, {:http_error, status}}

        {:error, reason} ->
          Logger.api_error("Character API request failed", error: inspect(reason))
          {:error, reason}

        other ->
          Logger.api_error("Unexpected result from character API", result: inspect(other))
          {:error, :unexpected_result}
      end

    case result do
      {:ok, _} = ok -> ok
      {:error, reason} -> fallback(cached, reason)
    end
  end

  @doc """
  Fetches character activity for `slug` (or default) over `days`.
  """
  @spec get_character_activity(String.t() | nil, pos_integer()) ::
          {:ok, map()} | {:error, reason()}
  def get_character_activity(slug \\ nil, days \\ 1) do
    url = activity_url(slug, days)
    headers = auth_header()

    Logger.api_debug("CharactersClient: fetching activity", url: url, days: days)

    with {:ok, %{status_code: 200, body: body}} <- HttpClient.get(url, headers),
         {:ok, decoded} <- decode_body(body) do
      {:ok, decoded}
    else
      {:ok, %{status_code: status, body: body}} ->
        Logger.api_error("CharactersClient activity HTTP error",
          status: status,
          body_preview: slice(body)
        )

        {:error, {:http_error, status}}

      {:error, reason} ->
        Logger.api_error("CharactersClient activity failed", error: inspect(reason))
        {:error, reason}
    end
  end

  # ——————— Helpers ——————— #

  # Build URLs & headers
  defp characters_url,
    do: "#{Config.base_map_url()}/api/map/user_characters?slug=#{Config.map_slug()}"

  defp activity_url(nil, days),
    do: "#{Config.base_map_url()}/map/characters/activity?days=#{days}"

  defp activity_url(slug, days),
    do: "#{Config.base_map_url()}/map/characters/#{slug}/activity?days=#{days}"

  defp auth_header,
    do: [{"Authorization", "Bearer #{Config.map_token()}"}]

  # Decode JSON or pass through map
  defp decode_body(body) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, data} -> {:ok, data}
      _ -> {:error, :json_decode_failed}
    end
  end

  defp decode_body(map) when is_map(map), do: {:ok, map}
  defp decode_body(_), do: {:error, :invalid_body}

  # Pull out the list of character maps
  defp extract_characters(%{"data" => groups}) when is_list(groups) do
    Logger.api_debug("Extracting characters from API response with #{length(groups)} groups")

    processed_groups =
      groups
      |> Enum.filter(&is_list(&1["characters"]))

    Logger.api_debug("Found #{length(processed_groups)} groups with character lists")

    # Log group structure for debugging
    if length(processed_groups) > 0 do
      sample_group = List.first(processed_groups)
      group_keys = Map.keys(sample_group)
      Logger.api_debug("Group structure keys", keys: inspect(group_keys))

      char_count = length(sample_group["characters"])
      Logger.api_debug("First group has #{char_count} characters")
    end

    characters = processed_groups |> Enum.flat_map(& &1["characters"])

    characters
  end

  defp extract_characters(other) do
    Logger.api_error("Failed to extract characters - unexpected API response format",
      response_type: inspect(other)
    )

    []
  end

  # Main processing pipeline: detect new, cache, notify
  defp process_and_cache(chars, cached, opts) do

    # Log a sample of the data for debugging
    if length(chars) > 0 do
      sample_char = List.first(chars)
      # Use only a few key fields to avoid logging sensitive data
      sample_fields = Map.take(sample_char, ["character_id", "corporation_id", "eve_id", "name"])
      Logger.api_debug("Sample character data structure", sample: inspect(sample_fields))
    end

    new_chars = detect_new(chars, cached)
    Logger.api_debug("New characters detected: #{length(new_chars)}")

    safe_cache(chars)
    maybe_notify_new(new_chars, cached, opts)
    {:ok, chars}
  rescue
    e ->
      Logger.api_error("CharactersClient processing failed",
        error: Exception.message(e)
      )

      {:error, :processing_error}
  end

  # Compare against cached eve_ids
  defp detect_new(chars, cached) do
    # Create a set of eve_ids from the cached list for faster lookup
    seen = MapSet.new(cached, & &1["eve_id"])

    Logger.api_debug(
      "Detecting new characters - API count: #{length(chars)}, cached IDs count: #{MapSet.size(seen)}"
    )

    # Log a few eve_ids from both sets to help with debugging
    if length(chars) > 0 do
      # Sample some ids for debugging
      sample_api_ids = chars |> Enum.take(3) |> Enum.map(& &1["eve_id"])
      Logger.api_debug("Sample API eve_ids", ids: inspect(sample_api_ids))
    end

    if MapSet.size(seen) > 0 do
      sample_cached_ids = MapSet.to_list(seen) |> Enum.take(3)
      Logger.api_debug("Sample cached eve_ids", ids: inspect(sample_cached_ids))
    end

    # Find characters in the API response that aren't in the cache
    new_chars = Enum.reject(chars, &(&1["eve_id"] in seen))

    # Log the result
    if length(new_chars) > 0 do
      Logger.api_info("Found #{length(new_chars)} new characters not in cache")
      new_sample = new_chars |> Enum.take(2) |> Enum.map(&Map.take(&1, ["eve_id", "name"]))
      Logger.api_debug("Sample new characters", sample: inspect(new_sample))
    end

    new_chars
  end

  # Write to cache with TTL
  defp safe_cache(chars) do
    ttl = Config.characters_cache_ttl()
    key = Keys.character_list()

    Logger.api_debug("Caching #{length(chars)} characters with TTL: #{ttl}s, key: #{inspect(key)}")

    case CachexImpl.set(key, chars, ttl) do
      :ok ->
        Logger.api_debug("Characters successfully cached")

      {:error, reason} ->
        Logger.api_error("Failed to cache characters", reason: inspect(reason))
    end
  rescue
    e ->
      Logger.api_error("CharactersClient cache error",
        error: Exception.message(e)
      )
  end

  # Send notifications for each truly new character, but only if cached is not empty
  # and suppress_notifications is not set
  defp maybe_notify_new([], _cached, _opts), do: :ok

  defp maybe_notify_new(_new_chars, [], _opts) do
    # Don't notify on empty cache (first run or error recovery)
    Logger.api_info("CharactersClient: skipping notifications on initial/empty cache load")
    :ok
  end

  defp maybe_notify_new(new_chars, _cached, opts) do
    # Check if notifications should be suppressed
    if Keyword.get(opts, :suppress_notifications, false) do
      Logger.api_info("CharactersClient: notifications suppressed by options")
      :ok
    else
      notify_new(new_chars)
    end
  end

  # Send notifications for each truly new character
  defp notify_new(new_chars) do
    Enum.each(new_chars, fn char_map ->
      char = MapCharacter.new(char_map)
      # ← use `character_id`, not `eve_id`
      if CharDeterminer.should_notify?(char.character_id, char) do
        Dispatcher.run(:send_new_tracked_character_notification, [char])
      end
    end)
  rescue
    e ->
      Logger.api_error("CharactersClient notify error",
        error: Exception.message(e)
      )
  end

  # If anything blows up, fall back to cache if available
  defp fallback(cached, reason) when is_list(cached) and cached != [] do
    Logger.api_info(
      "CharactersClient using #{length(cached)} cached characters as fallback",
      reason: inspect(reason)
    )

    {:ok, cached}
  end

  defp fallback([], reason) do
    Logger.api_error("CharactersClient fallback with empty cache", reason: inspect(reason))
    {:error, reason}
  end

  defp fallback(nil, reason) do
    Logger.api_error("CharactersClient fallback with nil cache", reason: inspect(reason))
    {:error, reason}
  end

  defp fallback(other, reason) do
    Logger.api_error("CharactersClient fallback with invalid cache type",
      cache_type: inspect(other),
      reason: inspect(reason)
    )

    {:error, reason}
  end

  # Preview for logging
  defp slice(body) when is_binary(body), do: String.slice(body, 0, 200)
  defp slice(_), do: ""
end
