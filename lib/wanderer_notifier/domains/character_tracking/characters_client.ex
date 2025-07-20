defmodule WandererNotifier.Domains.CharacterTracking.Client do
  @moduledoc """
  Client for fetching and managing character data from the map API.
  """

  use WandererNotifier.Map.Clients.BaseMapClient
  alias WandererNotifier.Shared.Logger.Logger, as: AppLogger
  alias WandererNotifier.Domains.CharacterTracking.Character
  alias WandererNotifier.Domains.Notifications.Determiner.Character, as: CharacterDeterminer
  alias WandererNotifier.Shared.Utils.ValidationUtils
  alias WandererNotifier.Shared.Utils.BatchProcessor

  # Use runtime configuration to avoid dialyzer issues with compile-time config
  @compile {:inline, requires_slug?: 0}

  @impl true
  def endpoint, do: "user-characters"

  @impl true
  def cache_key, do: "map:character_list"

  @impl true
  def cache_ttl, do: WandererNotifier.Infrastructure.Cache.ttl_for(:map_data)

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
    case ValidationUtils.validate_list(items, &valid_character?/1) do
      {:ok, _} ->
        :ok

      {:error, {:invalid_items, indices}} ->
        AppLogger.api_error("Characters data validation failed",
          count: length(items),
          invalid_indices: indices,
          error: "Invalid characters at positions: #{Enum.join(indices, ", ")}"
        )

        {:error, :invalid_data}
    end
  end

  def validate_data(other) do
    AppLogger.api_error("Invalid characters data type",
      type: ValidationUtils.type_name(other),
      error: "Expected list, got #{ValidationUtils.type_name(other)}"
    )

    {:error, :invalid_data}
  end

  defp valid_character?(character) do
    case ValidationUtils.validate_character_data(character) do
      {:ok, _} -> true
      {:error, _} -> false
    end
  end

  @impl true
  def should_notify?(character_id, character) do
    CharacterDeterminer.should_notify?(character_id, character)
  end

  @impl true
  def send_notification(character) do
    case WandererNotifier.Application.Services.NotificationService.notify_character(character) do
      :ok -> {:ok, :sent}
      :skip -> {:ok, :sent}
      error -> error
    end
  end

  @impl true
  def enrich_item(character) do
    # Normalize the character data - ensure we have eve_id field
    normalized = normalize_character_data(character)

    case Character.new_safe(normalized) do
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
      # Process characters using BatchProcessor
      # Smaller batches for character data due to enrichment complexity
      batch_size = 25

      final_characters =
        BatchProcessor.process_sync(characters, &enrich_item/1,
          batch_size: batch_size,
          # Slightly longer delay for character enrichment
          batch_delay: 100,
          log_progress: true,
          logger_metadata: %{
            operation: "process_characters",
            total_characters: length(characters)
          }
        )

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

  # Batch processing logic has been moved to BatchProcessor module
end
