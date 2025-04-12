defmodule WandererNotifier.Killmail.Processing.Processor do
  @moduledoc """
  Main entry point for killmail processing.

  This module orchestrates the entire killmail processing pipeline, including:
  - Data validation
  - Enrichment with additional information
  - Caching processed killmails
  - Persistence to database
  - Notification determination and delivery

  It provides a clean, unified interface for processing killmails from various sources.
  """

  @behaviour WandererNotifier.Killmail.Processing.ProcessorBehaviour

  alias WandererNotifier.Killmail.Core.{Data, Validator}

  alias WandererNotifier.Killmail.Processing.{
    Cache,
    Enrichment,
    NotificationDeterminer,
    Notification,
    Persistence
  }

  alias WandererNotifier.Logger.Logger, as: AppLogger

  # Use runtime dependency injection for easier testing
  defp validator, do: Application.get_env(:wanderer_notifier, :validator, Validator)
  defp enrichment, do: Application.get_env(:wanderer_notifier, :enrichment, Enrichment)
  defp cache, do: Application.get_env(:wanderer_notifier, :cache, Cache)

  defp persistence_module,
    do: Application.get_env(:wanderer_notifier, :persistence_module, Persistence)

  defp notification_determiner,
    do: Application.get_env(:wanderer_notifier, :notification_determiner, NotificationDeterminer)

  defp notification, do: Application.get_env(:wanderer_notifier, :notification, Notification)

  @doc """
  Processes a killmail through the complete pipeline.

  ## Parameters
    - killmail: The killmail data to process (Data struct or compatible map)
    - context: Optional processing context with metadata

  ## Returns
    - {:ok, processed_killmail} on successful processing
    - {:ok, :skipped} if the killmail was skipped
    - {:error, reason} on processing failure
  """
  @impl true
  @spec process_killmail(Data.t() | map(), map()) ::
          {:ok, Data.t()} | {:ok, :skipped} | {:error, any()}
  def process_killmail(killmail, context \\ %{}) do
    # Convert to Data struct if it's not already
    killmail_data = ensure_data_struct(killmail)

    # Log processing start
    AppLogger.kill_info("Processing killmail ##{killmail_data.killmail_id}")

    # Execute the processing pipeline
    with {:ok, valid_killmail} <- validate_killmail(killmail_data),
         {:ok, enriched_killmail} <- enrich_killmail(valid_killmail),
         {:ok, cached_killmail} <- cache_killmail(enriched_killmail),
         {:ok, persisted_killmail} <- persist_killmail(cached_killmail),
         {:ok, notification_result} <- determine_notification(persisted_killmail, context),
         :ok <- maybe_send_notification(notification_result, persisted_killmail) do
      # Log successful processing
      AppLogger.kill_info("Successfully processed killmail ##{persisted_killmail.killmail_id}")

      # Return the fully processed killmail
      {:ok, persisted_killmail}
    else
      # Special case for skipped killmails
      {:skip, reason} ->
        AppLogger.kill_debug("Skipped killmail processing: #{reason}")
        {:ok, :skipped}

      # Handle errors
      {:error, stage, reason} ->
        AppLogger.kill_error("Failed at #{stage} stage: #{inspect(reason)}")
        {:error, {stage, reason}}

      {:error, reason} ->
        AppLogger.kill_error("Failed to process killmail: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Initializes the processor during application startup.
  """
  @spec configure() :: :ok
  def configure do
    AppLogger.startup_info("Configuring killmail processor")
    :ok
  end

  # Private helper functions

  # Ensure we're working with a Data struct
  defp ensure_data_struct(%Data{} = killmail), do: killmail

  defp ensure_data_struct(killmail) when is_map(killmail) do
    # Convert map to Data struct
    case Data.from_map(killmail) do
      {:ok, data} ->
        data

      {:error, reason} ->
        AppLogger.kill_error("Failed to convert to Data struct: #{inspect(reason)}")
        # Create a minimal struct to continue processing
        %Data{
          killmail_id: Map.get(killmail, "killmail_id") || Map.get(killmail, :killmail_id),
          raw_data: killmail
        }
    end
  end

  # Validate the killmail data
  defp validate_killmail(killmail) do
    case validator().validate(killmail) do
      :ok ->
        {:ok, killmail}

      # This case won't actually happen with the current validator implementation,
      # but we keep it for future compatibility
      {:skip, reason} when is_binary(reason) ->
        {:skip, reason}

      {:error, errors} ->
        validator().log_validation_errors(killmail, errors)
        {:error, :validation, errors}
    end
  end

  # Enrich the killmail with additional data
  defp enrich_killmail(killmail) do
    case enrichment().enrich(killmail) do
      {:ok, enriched} -> {:ok, enriched}
      error -> error
    end
  end

  # Cache the killmail in memory
  defp cache_killmail(killmail) do
    # Check if already in cache first
    if cache().in_cache?(killmail.killmail_id) do
      AppLogger.kill_debug("Killmail ##{killmail.killmail_id} already in cache")
      {:ok, killmail}
    else
      cache().cache(killmail)
    end
  end

  # Persist the killmail to storage
  defp persist_killmail(killmail) do
    persistence_module().persist(killmail)
  end

  # Determine if a notification should be sent
  defp determine_notification(killmail, context) do
    # Check if we should force notifications from context
    force_notify = Map.get(context, :force_notification, false)

    if force_notify do
      AppLogger.kill_debug("Forcing notification for killmail ##{killmail.killmail_id}")
      {:ok, {true, "Notification forced"}}
    else
      notification_determiner().should_notify?(killmail)
    end
  end

  # Send notification if needed
  defp maybe_send_notification({should_notify, reason}, killmail) do
    if should_notify do
      AppLogger.kill_debug(
        "Sending notification for killmail ##{killmail.killmail_id}: #{reason}"
      )

      notification().notify(killmail)
    else
      AppLogger.kill_debug(
        "Not sending notification for killmail ##{killmail.killmail_id}: #{reason}"
      )

      :ok
    end
  end
end
