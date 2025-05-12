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

    Logger.api_debug("CharactersClient: fetching characters", url: url)

    result =
      with {:ok, %{status_code: 200, body: body}} <- HttpClient.get(url, headers),
           {:ok, decoded} <- decode_body(body),
           chars when is_list(chars) <- extract_characters(decoded) do
        process_and_cache(chars, cached, opts)
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
    groups
    |> Enum.filter(&is_list(&1["characters"]))
    |> Enum.flat_map(& &1["characters"])
  end

  defp extract_characters(_), do: []

  # Main processing pipeline: detect new, cache, notify
  defp process_and_cache(chars, cached, opts) do
    new_chars = detect_new(chars, cached)
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
    seen = MapSet.new(cached, & &1["eve_id"])
    Enum.reject(chars, &(&1["eve_id"] in seen))
  end

  # Write to cache with TTL
  defp safe_cache(chars) do
    ttl = Config.characters_cache_ttl()
    CachexImpl.set(Keys.character_list(), chars, ttl)
    Logger.api_debug("CharactersClient cached #{length(chars)} characters")
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
      "CharactersClient using #{length(cached)} cached characters (fallback: #{inspect(reason)})"
    )

    {:ok, cached}
  end

  defp fallback(_, reason), do: {:error, reason}

  # Preview for logging
  defp slice(body) when is_binary(body), do: String.slice(body, 0, 200)
  defp slice(_), do: ""
end
