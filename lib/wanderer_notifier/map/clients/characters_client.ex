defmodule WandererNotifier.Map.Clients.CharactersClient do
  @moduledoc """
  Client for fetching and managing character data from the map API.
  """

  use WandererNotifier.Map.Clients.BaseMapClient
  alias WandererNotifier.Logger.Logger, as: AppLogger
  alias WandererNotifier.Map.MapCharacter
  alias WandererNotifier.Cache.Keys, as: CacheKeys
  alias WandererNotifier.Notifications.Determiner.Character, as: CharacterDeterminer
  alias WandererNotifier.Notifiers.Discord.Notifier, as: DiscordNotifier

  # Use runtime configuration to avoid dialyzer issues with compile-time config
  @compile {:inline, requires_slug?: 0}

  @impl true
  def endpoint, do: "user-characters"

  @impl true
  def cache_key, do: CacheKeys.character_list()

  @impl true
  def cache_ttl, do: WandererNotifier.Cache.Config.ttl_for(:map_data)

  @impl true
  def requires_slug? do
    Application.get_env(:wanderer_notifier, :map_requires_slug?, true)
  end

  @impl true
  def extract_data(%{"data" => data}) when is_list(data) do
    # Flatten the nested structure to get all characters
    characters =
      data
      |> Enum.flat_map(fn
        %{"characters" => chars} when is_list(chars) -> chars
        _ -> []
      end)

    # Log sample character structure
    if length(characters) > 0 do
      AppLogger.api_info("Sample character from API",
        first_character: inspect(List.first(characters))
      )
    end

    {:ok, characters}
  end

  def extract_data(_), do: {:error, :invalid_data_format}

  @impl true
  def validate_data(items) when is_list(items) do
    if Enum.all?(items, &valid_character?/1), do: :ok, else: {:error, :invalid_data}
  end

  def validate_data(_), do: {:error, :invalid_data}

  defp valid_character?(character) when is_map(character) do
    # Check for either eve_id or character_eve_id (API might return either)
    has_eve_id = Map.has_key?(character, "eve_id") or Map.has_key?(character, "character_eve_id")
    has_name = Map.has_key?(character, "name")

    has_eve_id and has_name
  end

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
    # Normalize the character data - ensure we have eve_id field
    normalized = normalize_character_data(character)

    case MapCharacter.new_safe(normalized) do
      {:ok, struct} ->
        struct

      {:error, reason} ->
        AppLogger.api_error("Failed to create MapCharacter struct",
          error: reason,
          character: inspect(normalized)
        )

        normalized
    end
  end

  defp normalize_character_data(character) do
    # Ensure we have eve_id field (might be character_eve_id in some responses)
    eve_id = Map.get(character, "eve_id") || Map.get(character, "character_eve_id")

    character
    |> Map.put("eve_id", eve_id)
    |> Map.put("character_eve_id", eve_id)
  end

  @impl true
  def process_data(new_characters, _cached_characters, _opts) do
    AppLogger.api_info("Processing characters data",
      count: length(new_characters)
    )

    {:ok, new_characters}
  end

  @doc """
  Fetches characters from the API and populates the cache.
  This is used during initialization to ensure we have character data.
  Uses memory-efficient sequential processing to prevent startup spikes.
  """
  def fetch_and_cache_characters do
    AppLogger.api_info("Fetching characters from API for initialization (memory-efficient mode)")

    with {:ok, decoded} <-
           WandererNotifier.Map.Clients.BaseMapClient.fetch_and_decode(api_url(), headers()),
         {:ok, characters} <- extract_data(decoded),
         :ok <- validate_data(characters) do
      # Process characters in smaller batches to prevent memory spikes
      # Smaller batches for character data
      batch_size = 25
      batched_characters = Enum.chunk_every(characters, batch_size)

      AppLogger.api_info("Processing characters in batches",
        total_characters: length(characters),
        batch_size: batch_size,
        batch_count: length(batched_characters)
      )

      # Process each batch with a small delay for GC
      # Process characters and reverse the final result to maintain original order
      final_characters =
        batched_characters
        |> process_characters_in_batches([])
        |> Enum.reverse()

      # Cache all processed characters at once
      WandererNotifier.Map.Clients.BaseMapClient.cache_put(
        cache_key(),
        final_characters,
        cache_ttl()
      )
    else
      error ->
        AppLogger.api_error("Failed to fetch and cache characters", error: inspect(error))
        error
    end
  end

  defp process_characters_in_batches([], accumulated) do
    # Return the accumulated list in correct order
    accumulated
  end

  defp process_characters_in_batches([batch | remaining_batches], accumulated) do
    # Process current batch
    processed_batch = Enum.map(batch, &enrich_item/1)

    # Add small delay between batches to allow garbage collection
    # Slightly longer delay for character enrichment
    Process.sleep(100)

    # Continue with remaining batches
    # Prepend processed_batch items in reverse order to maintain original order
    # This avoids O(n²) complexity from repeated list concatenation
    new_accumulated =
      processed_batch
      |> Enum.reverse()
      |> Enum.reduce(accumulated, fn item, acc ->
        [item | acc]
      end)

    process_characters_in_batches(remaining_batches, new_accumulated)
  end
end
