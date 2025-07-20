defmodule WandererNotifier.Domains.SystemTracking.Client do
  @moduledoc """
  Client for fetching and caching system data from the EVE Online Map API.
  """

  use WandererNotifier.Map.Clients.BaseMapClient
  alias WandererNotifier.Shared.Logger.Logger, as: AppLogger
  alias WandererNotifier.Domains.Notifications.Determiner.System, as: SystemDeterminer
  alias WandererNotifier.Infrastructure.Cache
  alias WandererNotifier.Shared.Utils.ValidationUtils
  alias WandererNotifier.Shared.Utils.BatchProcessor

  @default_batch_size 50
  @batch_size_config_key :map_systems_batch_size

  @impl true
  def endpoint, do: "systems"

  @impl true
  def extract_data(%{"data" => %{"systems" => systems}}) do
    {:ok, systems}
  end

  def extract_data(data) do
    AppLogger.api_error("Invalid systems data format",
      data: inspect(data)
    )

    {:error, :invalid_data_format}
  end

  @impl true
  def validate_data(systems) when is_list(systems) do
    case ValidationUtils.validate_list(systems, &valid_system?/1) do
      {:ok, _} ->
        :ok

      {:error, {:invalid_items, indices}} ->
        AppLogger.api_error("Systems data validation failed",
          count: length(systems),
          invalid_indices: indices,
          error: "Invalid systems at positions: #{Enum.join(indices, ", ")}"
        )

        {:error, :invalid_data}
    end
  end

  def validate_data(other) do
    AppLogger.api_error("Invalid systems data type",
      type: ValidationUtils.type_name(other),
      error: "Expected list, got #{ValidationUtils.type_name(other)}"
    )

    {:error, :invalid_data}
  end

  @impl true
  def process_data(new_systems, _cached_systems, _opts) do
    AppLogger.api_info("Processing systems data",
      count: length(new_systems)
    )

    {:ok, new_systems}
  end

  @impl true
  def cache_key, do: Cache.Keys.map_systems()

  @impl true
  def cache_ttl, do: WandererNotifier.Infrastructure.Cache.map_ttl()

  @impl true
  def should_notify?(system_id, system) do
    SystemDeterminer.should_notify?(system_id, system)
  end

  @impl true
  def send_notification(system) do
    case WandererNotifier.Application.Services.NotificationService.notify_system(system.name) do
      :ok -> {:ok, :sent}
      :skip -> {:ok, :sent}
      error -> error
    end
  end

  @impl true
  def enrich_item(system) do
    case WandererNotifier.Domains.SystemTracking.StaticInfo.enrich_system(system) do
      {:ok, enriched} -> enriched
    end
  end

  defp valid_system?(system) do
    case ValidationUtils.validate_system_data(system) do
      {:ok, _} -> true
      {:error, _} -> false
    end
  end

  @doc """
  Fetches systems from the API and populates the cache.
  This is used during initialization to ensure we have system data.
  Uses memory-efficient sequential processing to prevent startup spikes.
  """
  def fetch_and_cache_systems do
    AppLogger.api_info("Fetching systems from API for initialization (memory-efficient mode)")

    with {:ok, decoded} <-
           WandererNotifier.Map.Clients.BaseMapClient.fetch_and_decode(api_url(), headers()),
         {:ok, systems} <- extract_data(decoded),
         :ok <- validate_data(systems) do
      # Process systems using BatchProcessor
      batch_size = get_batch_size()

      final_systems =
        BatchProcessor.process_sync(systems, &enrich_item/1,
          batch_size: batch_size,
          batch_delay: 50,
          log_progress: true,
          logger_metadata: %{
            operation: "process_systems",
            total_systems: length(systems)
          }
        )

      # Cache all processed systems at once using centralized Cache module
      WandererNotifier.Infrastructure.Cache.put_with_ttl(
        cache_key(),
        final_systems,
        cache_ttl()
      )
    else
      error ->
        AppLogger.api_error("Failed to fetch and cache systems", error: inspect(error))
        error
    end
  end

  # Batch processing logic has been moved to BatchProcessor module

  defp get_batch_size do
    Application.get_env(:wanderer_notifier, @batch_size_config_key, @default_batch_size)
  end
end
