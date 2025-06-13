defmodule WandererNotifier.Map.Clients.CharactersClient do
  @moduledoc """
  Client for fetching and managing character data from the map API.
  """

  use WandererNotifier.Map.Clients.BaseMapClient
  alias WandererNotifier.Logger.Logger, as: AppLogger
  alias WandererNotifier.Map.MapCharacter
  alias WandererNotifier.Notifications.Determiner.Character, as: CharacterDeterminer
  alias WandererNotifier.Notifiers.Discord.Notifier, as: DiscordNotifier

  @impl true
  def endpoint, do: "user-characters"

  @impl true
  def cache_key, do: "characters"

  @impl true
  def cache_ttl, do: WandererNotifier.Cache.Config.ttl_for(:map_data)

  @impl true
  def extract_data(%{"data" => data}) when is_list(data) do
    # Flatten the nested structure to get all characters
    characters =
      data
      |> Enum.flat_map(fn
        %{"characters" => chars} when is_list(chars) -> chars
        _ -> []
      end)

    {:ok, characters}
  end

  def extract_data(_), do: {:error, :invalid_data_format}

  @impl true
  def validate_data(items) when is_list(items) do
    if Enum.all?(items, &valid_character?/1), do: :ok, else: {:error, :invalid_data}
  end

  defp valid_character?(%{"eve_id" => eve_id, "name" => name})
       when is_binary(eve_id) and is_binary(name),
       do: true

  defp valid_character?(_), do: false

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
    # Convert the plain map to a MapCharacter struct
    # This ensures the notification function receives the expected struct type
    try do
      MapCharacter.new(character)
    rescue
      e ->
        AppLogger.api_error("Failed to create MapCharacter struct",
          error: Exception.message(e),
          character: inspect(character)
        )

        # Return the original character if struct creation fails
        character
    end
  end

  @impl true
  def process_data(new_characters, _cached_characters, _opts) do
    AppLogger.api_info("Processing characters data",
      count: length(new_characters)
    )

    {:ok, new_characters}
  end
end
