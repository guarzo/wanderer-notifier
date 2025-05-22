defmodule WandererNotifier.Map.Clients.CharactersClient do
  @moduledoc """
  Client for fetching and caching character data from the EVE Online Map API.
  """

  use WandererNotifier.Map.Clients.BaseMapClient
  alias WandererNotifier.Logger.Logger, as: AppLogger
  alias WandererNotifier.Notifications.Determiner.Character, as: CharacterDeterminer
  alias WandererNotifier.Notifiers.Discord.Notifier, as: DiscordNotifier
  alias WandererNotifier.Cache.Keys, as: CacheKeys

  @impl true
  def endpoint, do: "user-characters"

  @impl true
  def extract_data(%{"data" => data}) when is_list(data) do
    # Extract characters from each group
    characters =
      Enum.flat_map(data, fn group ->
        case group do
          %{"characters" => chars} when is_list(chars) -> chars
          _ -> []
        end
      end)

    {:ok, characters}
  end

  def extract_data(data) do
    AppLogger.api_error("Invalid characters data format",
      data: inspect(data, pretty: true)
    )

    {:error, :invalid_data_format}
  end

  @impl true
  def validate_data(characters) when is_list(characters) do
    if Enum.all?(characters, &valid_character?/1) do
      :ok
    else
      AppLogger.api_error("Characters data validation failed",
        count: length(characters)
      )

      {:error, :invalid_data}
    end
  end

  def validate_data(other) do
    AppLogger.api_error("Invalid characters data type",
      type: inspect(other)
    )

    {:error, :invalid_data}
  end

  @impl true
  def process_data(new_characters, _cached_characters, _opts) do
    # For now, just return the new characters
    # In the future, we could implement diffing or other processing here
    AppLogger.api_info("Processing characters data",
      count: length(new_characters)
    )

    {:ok, new_characters}
  end

  @impl true
  def cache_key, do: CacheKeys.character_list()

  @impl true
  def cache_ttl, do: 300

  @impl true
  def should_notify?(character_id, character) do
    CharacterDeterminer.should_notify?(character_id, character)
  end

  @impl true
  def send_notification(character) do
    DiscordNotifier.send_new_tracked_character_notification(character)
  end

  @impl true
  def enrich_item(character) do
    # For now, just return the character as is
    # In the future, we could add character-specific enrichment
    character
  end

  defp valid_character?(character) do
    is_map(character) and
      is_binary(character["name"]) and
      (is_binary(character["eve_id"]) or is_integer(character["eve_id"])) and
      is_binary(character["corporation_ticker"]) and
      (is_binary(character["corporation_id"]) or is_integer(character["corporation_id"])) and
      (is_binary(character["alliance_id"]) or is_integer(character["alliance_id"]) or
         is_nil(character["alliance_id"]))
  end
end
