defmodule WandererNotifier.Killmail.Processing.Processor do
  @moduledoc """
  A unified processor for killmail events that coordinates the entire lifecycle:
  validation, enrichment, persistence, and notification.

  This module serves as the primary entry point for killmail processing,
  consolidating logic that was previously scattered across multiple modules.
  """

  require Logger
  alias WandererNotifier.Api.ESI.Service, as: ESIService
  alias WandererNotifier.Killmail.Core.Data
  alias WandererNotifier.Killmail.Core.Validator
  alias WandererNotifier.Killmail.Processing.Enrichment
  alias WandererNotifier.Killmail.Processing.NotificationDeterminer
  alias WandererNotifier.Killmail.Processing.Notification
  alias WandererNotifier.Killmail.Processing.Persistence
  alias WandererNotifier.Logger.Logger, as: AppLogger

  @doc """
  Process a killmail through the complete pipeline.

  This function orchestrates the entire lifecycle of killmail processing:
  1. Normalizes the input data to Data format
  2. Validates the killmail data
  3. Enriches it with additional information
  4. Persists it to the database if appropriate
  5. Sends notifications if needed

  ## Parameters
    - killmail: Raw killmail data from zKillboard or ESI
    - context: Processing context with metadata about the source and mode

  ## Returns
    - {:ok, result} on success with the processed killmail
    - {:ok, :skipped} if explicitly skipped
    - {:error, reason} on failure
  """
  def process_killmail(killmail, context) do
    with {:ok, normalized} <- normalize_killmail(killmail),
         {:ok, validated} <- validate_killmail(normalized),
         {:ok, enriched} <- enrich_killmail(validated),
         {:ok, persisted, should_notify} <- persist_killmail(enriched, context),
         {:ok, result} <- notify_if_needed(persisted, should_notify, context) do
      AppLogger.kill_info("Successfully processed killmail ##{normalized.killmail_id}")
      {:ok, result}
    else
      # Handle explicit skipping
      {:error, {:skipped, reason}} ->
        AppLogger.kill_info("Killmail processing skipped: #{reason}")
        {:ok, :skipped}

      # Handle validation errors
      {:error, {:validation, errors}} ->
        kill_id = extract_killmail_id(killmail)

        AppLogger.kill_error("Validation failed for killmail ##{kill_id}", %{
          errors: inspect(errors)
        })

        {:error, {:validation, errors}}

      # Handle enrichment errors
      {:error, {:enrichment, reason}} ->
        kill_id = extract_killmail_id(killmail)
        AppLogger.kill_error("Enrichment failed for killmail ##{kill_id}: #{inspect(reason)}")
        {:error, {:enrichment, reason}}

      # Handle persistence errors
      {:error, {:persistence, reason}} ->
        kill_id = extract_killmail_id(killmail)
        AppLogger.kill_error("Persistence failed for killmail ##{kill_id}: #{inspect(reason)}")
        {:error, {:persistence, reason}}

      # Handle other errors
      error ->
        kill_id = extract_killmail_id(killmail)
        AppLogger.kill_error("Error processing killmail ##{kill_id}: #{inspect(error)}")
        error
    end
  end

  # Normalizes any killmail format to the standard Data struct
  defp normalize_killmail(killmail) do
    # Extract killmail_id and hash from the raw data if possible
    kill_id = extract_killmail_id(killmail)
    hash = extract_hash(killmail)

    AppLogger.kill_debug("Normalizing killmail ##{kill_id}")

    # Determine if we need to fetch ESI data or already have it
    cond do
      # Already a Data struct, return as is
      is_struct(killmail, Data) ->
        {:ok, killmail}

      # Has both killmail_id and hash, fetch from ESI and create Data
      kill_id != nil && hash != nil ->
        fetch_esi_data_and_create_killmail(kill_id, hash, killmail)

      # Missing required data
      true ->
        {:error, {:skipped, "Missing killmail_id or hash"}}
    end
  end

  # Extract killmail_id from any format
  defp extract_killmail_id(killmail) do
    # Simple extraction initially - will be enhanced
    cond do
      is_struct(killmail, Data) -> killmail.killmail_id
      is_map(killmail) && Map.has_key?(killmail, :killmail_id) -> killmail.killmail_id
      is_map(killmail) && Map.has_key?(killmail, "killmail_id") -> killmail["killmail_id"]
      true -> nil
    end
  end

  # Extract hash from any format
  defp extract_hash(killmail) do
    # Simple extraction initially - will be enhanced
    cond do
      is_struct(killmail, Data) && is_binary(killmail.zkb_hash) ->
        killmail.zkb_hash

      is_struct(killmail, Data) && is_map(killmail.raw_zkb_data) ->
        Map.get(killmail.raw_zkb_data, "hash")

      is_map(killmail) && Map.has_key?(killmail, :zkb_data) ->
        Map.get(killmail.zkb_data, "hash")

      is_map(killmail) && Map.has_key?(killmail, "zkb") ->
        Map.get(killmail["zkb"], "hash")

      is_map(killmail) && Map.has_key?(killmail, :zkb) ->
        Map.get(killmail.zkb, "hash")

      true ->
        nil
    end
  end

  # Fetch ESI data and create a Data struct
  defp fetch_esi_data_and_create_killmail(kill_id, hash, zkb_data) do
    AppLogger.kill_debug("Fetching ESI data for killmail ##{kill_id} with hash #{hash}")

    case ESIService.get_killmail(kill_id, hash) do
      {:ok, esi_data} ->
        # Create a Data struct from the zkb and ESI data
        Data.from_zkb_and_esi(zkb_data, esi_data)

      {:error, :not_found} ->
        AppLogger.kill_debug("ESI data not found for killmail ##{kill_id}")
        {:error, {:skipped, "ESI data not available"}}

      {:error, reason} ->
        AppLogger.kill_error(
          "Error fetching ESI data for killmail ##{kill_id}: #{inspect(reason)}"
        )

        {:error, {:esi_error, reason}}
    end
  end

  # Validates the killmail data
  defp validate_killmail(killmail) do
    AppLogger.kill_debug("Validating killmail ##{killmail.killmail_id}")

    case Validator.validate(killmail) do
      :ok ->
        {:ok, killmail}

      {:error, errors} ->
        # Log the validation errors
        Validator.log_validation_errors(killmail, errors)

        # Check if we have minimum required data to continue
        if Validator.has_minimum_required_data?(killmail) do
          # We can continue with warnings
          AppLogger.kill_warn(
            "Continuing with incomplete killmail ##{killmail.killmail_id} (has minimum data)"
          )

          {:ok, killmail}
        else
          # We don't have enough data to continue
          {:error, {:validation, errors}}
        end
    end
  end

  # Enriches the killmail with additional data
  defp enrich_killmail(killmail) do
    AppLogger.kill_debug("Enriching killmail ##{killmail.killmail_id}")

    # Call the dedicated Enrichment module
    case Enrichment.enrich(killmail) do
      {:ok, enriched} ->
        {:ok, enriched}

      {:error, reason} ->
        {:error, {:enrichment, reason}}
    end
  end

  # Persists the killmail to the database if appropriate
  defp persist_killmail(killmail, context) do
    AppLogger.kill_debug("Checking if killmail ##{killmail.killmail_id} should be persisted")

    # Check if we should even try to persist based on tracking rules
    case should_process_kill?(killmail) do
      {true, reason} ->
        # This is a tracked kill, try to persist
        AppLogger.kill_debug("Persisting tracked killmail ##{killmail.killmail_id}: #{reason}")
        do_persist_killmail(killmail, context)

      {false, reason} ->
        # Not tracked, skip persistence
        AppLogger.kill_info(
          "Skipping persistence for killmail ##{killmail.killmail_id}: #{reason}"
        )

        # Return killmail with persisted=false but forward for notification check
        case NotificationDeterminer.should_notify?(killmail) do
          {:ok, {should_notify, _reason}} ->
            # Return the unpersisted killmail with notification decision
            {:ok, %{killmail | persisted: false}, should_notify}

          {:error, _reason} ->
            # On error, assume we shouldn't notify
            {:ok, %{killmail | persisted: false}, false}
        end
    end
  end

  # Determines if a killmail should be processed based on tracking rules
  defp should_process_kill?(killmail) do
    # Use the NotificationDeterminer to check if it should be processed
    case NotificationDeterminer.should_notify?(killmail) do
      {:ok, {true, reason}} ->
        # Should be processed
        {true, reason}

      {:ok, {false, reason}} ->
        # Should not be processed
        {false, reason}

      {:error, _reason} ->
        # On error, assume we should process it to be safe
        {true, "Error determining if kill should be processed"}
    end
  end

  # Actually persists the killmail to the database
  defp do_persist_killmail(killmail, context) do
    # Get the character_id from context if available
    character_id = Map.get(context, :character_id)

    # Use the dedicated Persistence module
    case Persistence.persist_killmail(killmail, character_id) do
      {:ok, persisted_killmail, _created} ->
        # Persistence successful, check if we should notify
        case NotificationDeterminer.should_notify?(persisted_killmail) do
          {:ok, {should_notify, _reason}} ->
            # Return the persisted killmail and notification decision
            {:ok, persisted_killmail, should_notify}

          {:error, reason} ->
            # Error determining notification, log but don't fail the process
            AppLogger.kill_error(
              "Error determining notification for killmail ##{killmail.killmail_id}: #{inspect(reason)}"
            )

            # Assume we shouldn't notify
            {:ok, persisted_killmail, false}
        end

      {:error, reason} ->
        # Persistence failed
        {:error, {:persistence, reason}}
    end
  end

  # Sends notification if needed
  defp notify_if_needed(killmail, false, _context) do
    # Skip notification
    {:ok, killmail}
  end

  defp notify_if_needed(killmail, true, _context) do
    AppLogger.kill_debug("Sending notification for killmail ##{killmail.killmail_id}")

    # Use the dedicated Notification module
    case Notification.send_kill_notification(killmail, killmail.killmail_id) do
      {:ok, _notification} ->
        # Notification sent successfully
        AppLogger.kill_info("Notification sent for killmail ##{killmail.killmail_id}")
        {:ok, killmail}

      {:error, reason} ->
        # Error sending notification, but don't fail the processing
        AppLogger.kill_error(
          "Error sending notification for killmail ##{killmail.killmail_id}: #{inspect(reason)}"
        )

        # Still return success since notification is non-critical
        {:ok, killmail}
    end
  end

  @doc """
  Configure the Processor module during application startup.
  This function is called by the Application module during startup.
  """
  def configure do
    AppLogger.info("Configuring Processor module")
    # Add any required configuration here
    :ok
  end
end
