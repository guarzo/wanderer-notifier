defmodule WandererNotifier.Domains.Tracking.Clients.UnifiedClient do
  @moduledoc """
  Unified tracking client that handles both character and system tracking with shared infrastructure.

  This module consolidates the common patterns between character and system tracking while
  preserving domain-specific functionality through entity-specific configurations.
  """

  use WandererNotifier.Map.Clients.BaseMapClient
  alias WandererNotifier.Shared.Logger.Logger, as: AppLogger
  alias WandererNotifier.Shared.Utils.{ValidationUtils, BatchProcessor}
  alias WandererNotifier.Infrastructure.Cache
  alias WandererNotifier.Domains.Notifications.Determiner
  alias WandererNotifier.Application.Services.NotificationService

  # Entity type configurations
  @entity_configs %{
    characters: %{
      endpoint: "user-characters",
      cache_key: "map:character_list",
      batch_size: 25,
      batch_delay: 100,
      requires_slug: true,
      determiner: Determiner.Character,
      validator: :validate_character_data,
      enricher: &__MODULE__.enrich_character/1,
      notifier: &NotificationService.notify_character/1,
      extract_path: ["data", "characters"]
    },
    systems: %{
      endpoint: "systems",
      cache_key: "map:systems",
      batch_size: 50,
      batch_delay: 50,
      requires_slug: false,
      determiner: Determiner.System,
      validator: :validate_system_data,
      enricher: &__MODULE__.enrich_system/1,
      notifier: &__MODULE__.notify_system_by_name/1,
      extract_path: ["data", "systems"]
    }
  }

  # ══════════════════════════════════════════════════════════════════════════════
  # BaseMapClient Implementation (Generic)
  # ══════════════════════════════════════════════════════════════════════════════

  @impl true
  def endpoint do
    get_entity_config(:endpoint, "")
  end

  @impl true
  def cache_key do
    get_entity_config(:cache_key, "map:unknown")
  end

  @impl true
  def cache_ttl do
    Cache.ttl_for(:map_data)
  end

  @impl true
  def requires_slug? do
    get_entity_config(:requires_slug, false)
  end

  @impl true
  def extract_data(response) do
    entity_type = get_current_entity_type()
    config = @entity_configs[entity_type]
    extract_path = config.extract_path

    case extract_nested_data(response, extract_path) do
      {:ok, data} ->
        # Handle different response structures
        case {entity_type, data} do
          {:characters, data} when is_list(data) ->
            # Flatten nested character structure
            characters =
              data
              |> Enum.flat_map(fn
                %{"characters" => chars} when is_list(chars) -> chars
                _ -> []
              end)

            {:ok, characters}

          {:systems, data} when is_list(data) ->
            {:ok, data}

          {_, data} when is_list(data) ->
            {:ok, data}

          _ ->
            {:error, :invalid_data_format}
        end

      error ->
        error
    end
  end

  @impl true
  def validate_data(items) when is_list(items) do
    entity_type = get_current_entity_type()
    config = @entity_configs[entity_type]

    validator_fun = fn item ->
      case ValidationUtils.apply(config.validator, [item]) do
        {:ok, _} -> true
        {:error, _} -> false
      end
    end

    case ValidationUtils.validate_list(items, validator_fun) do
      {:ok, _} ->
        :ok

      {:error, {:invalid_items, indices}} ->
        AppLogger.api_error("#{entity_type} data validation failed",
          count: length(items),
          invalid_indices: indices,
          error: "Invalid #{entity_type} at positions: #{Enum.join(indices, ", ")}"
        )

        {:error, :invalid_data}
    end
  end

  def validate_data(other) do
    entity_type = get_current_entity_type()

    AppLogger.api_error("Invalid #{entity_type} data type",
      type: ValidationUtils.type_name(other),
      error: "Expected list, got #{ValidationUtils.type_name(other)}"
    )

    {:error, :invalid_data}
  end

  @impl true
  def should_notify?(entity_id, entity) do
    entity_type = get_current_entity_type()
    config = @entity_configs[entity_type]
    config.determiner.should_notify?(entity_id, entity)
  end

  @impl true
  def send_notification(entity) do
    entity_type = get_current_entity_type()
    config = @entity_configs[entity_type]

    case config.notifier.(entity) do
      :ok -> {:ok, :sent}
      {:error, :notifications_disabled} -> {:ok, :sent}
      :skip -> {:ok, :sent}
      error -> error
    end
  end

  @impl true
  def enrich_item(item) do
    entity_type = get_current_entity_type()
    config = @entity_configs[entity_type]
    config.enricher.(item)
  end

  @impl true
  def process_data(new_items, _cached_items, _opts) do
    entity_type = get_current_entity_type()

    AppLogger.api_info("Processing #{entity_type} data",
      count: length(new_items)
    )

    {:ok, new_items}
  end

  # ══════════════════════════════════════════════════════════════════════════════
  # Public API - Entity-Specific Methods
  # ══════════════════════════════════════════════════════════════════════════════

  @doc """
  Fetches and caches character data from the map API.
  """
  def fetch_and_cache_characters do
    with_entity_context(:characters, fn ->
      fetch_and_cache_entities("characters")
    end)
  end

  @doc """
  Fetches and caches system data from the map API.
  """
  def fetch_and_cache_systems do
    with_entity_context(:systems, fn ->
      fetch_and_cache_entities("systems")
    end)
  end

  @doc """
  Generic method to fetch and cache entities with memory-efficient batch processing.
  """
  def fetch_and_cache_entities(entity_type_name) do
    entity_type = String.to_atom(entity_type_name)
    config = @entity_configs[entity_type]

    AppLogger.api_info(
      "Fetching #{entity_type_name} from API for initialization (memory-efficient mode)"
    )

    with {:ok, decoded} <-
           WandererNotifier.Map.Clients.BaseMapClient.fetch_and_decode(api_url(), headers()),
         {:ok, entities} <- extract_data(decoded),
         :ok <- validate_data(entities) do
      # Process entities using BatchProcessor with entity-specific configuration
      final_entities =
        BatchProcessor.process_sync(entities, &enrich_item/1,
          batch_size: config.batch_size,
          batch_delay: config.batch_delay,
          log_progress: true,
          logger_metadata: %{
            operation: "process_#{entity_type_name}",
            total_count: length(entities)
          }
        )

      # Cache all processed entities at once
      Cache.put_with_ttl(
        config.cache_key,
        final_entities,
        cache_ttl()
      )
    else
      error ->
        AppLogger.api_error("Failed to fetch and cache #{entity_type_name}",
          error: inspect(error)
        )

        error
    end
  end

  # ══════════════════════════════════════════════════════════════════════════════
  # Entity-Specific Enrichment Functions
  # ══════════════════════════════════════════════════════════════════════════════

  @doc """
  Enriches character data with normalized EVE ID and creates MapCharacter struct.
  """
  def enrich_character(character) do
    # Import the Character module for struct creation
    alias WandererNotifier.Domains.CharacterTracking.Character

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

  @doc """
  Enriches system data with static wormhole information.
  """
  def enrich_system(system) do
    case WandererNotifier.Domains.SystemTracking.StaticInfo.enrich_system(system) do
      {:ok, enriched} -> enriched
    end
  end

  # ══════════════════════════════════════════════════════════════════════════════
  # Entity-Specific Notification Functions
  # ══════════════════════════════════════════════════════════════════════════════

  @doc """
  Sends system notification by extracting system name.
  """
  def notify_system_by_name(system) do
    system_name =
      case system do
        %{name: name} -> name
        %{"name" => name} -> name
        _ -> "Unknown System"
      end

    NotificationService.notify_system(system_name)
  end

  # ══════════════════════════════════════════════════════════════════════════════
  # Private Helper Functions
  # ══════════════════════════════════════════════════════════════════════════════

  defp normalize_character_data(character) do
    # Ensure we have eve_id field (might be character_eve_id in some responses)
    eve_id = Map.get(character, "eve_id") || Map.get(character, "character_eve_id")

    character
    |> Map.put("eve_id", eve_id)
    |> Map.put("character_eve_id", eve_id)
  end

  defp extract_nested_data(response, path) do
    result =
      Enum.reduce_while(path, response, fn key, acc ->
        case acc do
          %{^key => value} -> {:cont, value}
          _ -> {:halt, {:error, :path_not_found}}
        end
      end)

    case result do
      {:error, reason} -> {:error, reason}
      data -> {:ok, data}
    end
  end

  # ══════════════════════════════════════════════════════════════════════════════
  # Process Variable Management (for entity context)
  # ══════════════════════════════════════════════════════════════════════════════

  defp with_entity_context(entity_type, fun) do
    old_type = Process.get(:current_entity_type)
    Process.put(:current_entity_type, entity_type)

    try do
      fun.()
    after
      case old_type do
        nil -> Process.delete(:current_entity_type)
        type -> Process.put(:current_entity_type, type)
      end
    end
  end

  defp get_current_entity_type do
    Process.get(:current_entity_type, :systems)
  end

  defp get_entity_config(key, default) do
    entity_type = get_current_entity_type()

    case @entity_configs[entity_type] do
      nil -> default
      config -> Map.get(config, key, default)
    end
  end
end
