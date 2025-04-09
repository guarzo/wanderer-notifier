defmodule WandererNotifier.KillmailProcessing.Pipeline do
  @moduledoc """
  Pipeline for processing killmail data from start to finish.
  Handles tasks like enrichment, validation, persistence, and notifications.
  """

  alias WandererNotifier.Api.ESI.Service, as: ESIService
  alias WandererNotifier.Core.Stats
  alias WandererNotifier.Data.KillmailEnrichment, as: Enrichment
  alias WandererNotifier.KillmailProcessing.{Context, Extractor, KillmailData, Metrics, Validator}
  alias WandererNotifier.Logger.Logger, as: AppLogger
  alias WandererNotifier.Notifications.Determiner.Kill, as: KillDeterminer
  alias WandererNotifier.Processing.Killmail.{Enrichment, Notification}
  alias WandererNotifier.Resources.Killmail, as: KillmailResource
  alias WandererNotifier.Resources.KillmailPersistence

  @type killmail :: KillmailResource.t() | KillmailData.t() | map()
  @type result :: {:ok, any()} | {:error, any()}

  @doc """
  Process a killmail through the pipeline.
  """
  @spec process_killmail(map(), Context.t()) :: result()
  def process_killmail(zkb_data, ctx) do
    Metrics.track_processing_start(ctx)
    Stats.increment(:kill_processed)

    with {:ok, killmail} <- create_normalized_killmail(zkb_data),
         {:ok, enriched} <- enrich_killmail_data(killmail),
         {:ok, validated_killmail} <- validate_killmail_data(enriched),
         {:ok, persisted} <- persist_normalized_killmail(validated_killmail, ctx),
         {:ok, should_notify, reason} <- check_notification(persisted, ctx),
         {:ok, result} <- maybe_send_notification(persisted, should_notify, ctx) do
      # Successfully processed killmail
      Metrics.track_processing_complete(ctx, {:ok, result})

      # Check if the killmail was updated in check_notification
      final_killmail = Process.get(:last_killmail_update) || result
      # Clean up after ourselves
      Process.delete(:last_killmail_update)

      # Check if killmail has a persisted flag set to false
      was_persisted =
        if is_map(final_killmail) && Map.has_key?(final_killmail, :persisted),
          do: Map.get(final_killmail, :persisted),
          else: true

      log_killmail_outcome(final_killmail, ctx,
        persisted: was_persisted,
        notified: should_notify,
        reason: reason
      )

      {:ok, final_killmail}
    else
      # Explicit skipping
      {:error, {:skipped, reason}} ->
        Metrics.track_processing_skipped(ctx)
        log_killmail_outcome(zkb_data, ctx, persisted: false, notified: false, reason: reason)
        {:ok, :skipped}

      # Validation failures
      {:error, {:enrichment_validation_failed, reasons}} ->
        # Log at error level since these are important issues
        AppLogger.kill_error("Killmail failed enrichment validation", %{
          reasons: reasons,
          killmail_id: zkb_data["killmail_id"] || "unknown"
        })

        Metrics.track_processing_error(ctx)
        {:error, :enrichment_validation_failed}

      {:error, :not_found} ->
        kill_id = Map.get(zkb_data, "killmail_id", "unknown")

        AppLogger.kill_info("ESI data not found for killmail", %{
          kill_id: kill_id
        })

        Metrics.track_processing_skipped(ctx)
        # Return the error for proper handling, but don't log as error
        {:error, :not_found}

      # For other errors, log at info level, not error - cut down on noise
      error ->
        Metrics.track_processing_error(ctx)
        # Use debug logging for these errors to reduce noise
        kill_id = get_kill_id(zkb_data)

        AppLogger.kill_info("Killmail processing issue", %{
          error: inspect(error),
          kill_id: kill_id,
          status: "failed"
        })

        # Return the error for proper handling
        error
    end
  end

  # Creates a normalized killmail from the zKillboard data
  @spec create_normalized_killmail(map()) :: result()
  defp create_normalized_killmail(zkb_data) do
    kill_id = Map.get(zkb_data, "killmail_id")
    hash = get_in(zkb_data, ["zkb", "hash"])

    AppLogger.kill_info("Fetching ESI data for killmail", %{
      kill_id: kill_id,
      hash: hash,
      zkb_keys: Map.keys(zkb_data)
    })

    case ESIService.get_killmail(kill_id, hash) do
      {:ok, esi_data} ->
        # Create normalized model using KillmailData
        AppLogger.kill_info("ESI data successfully retrieved", %{
          kill_id: kill_id,
          esi_data_keys: Map.keys(esi_data)
        })

        # Use KillmailData.from_zkb_and_esi to create structured data
        {:ok, KillmailData.from_zkb_and_esi(zkb_data, esi_data)}

      {:error, :not_found} ->
        # This is common and expected - ESI doesn't have data for this killmail yet
        # Log and return a specific error for this case (debug level, not error)
        AppLogger.kill_info("ESI data not found for killmail", %{
          kill_id: kill_id,
          hash: hash
        })

        {:error, {:skipped, "ESI data not available"}}

      error ->
        # Log as debug level rather than error - reduce noise
        AppLogger.kill_info("Error fetching killmail from ESI", %{
          kill_id: kill_id,
          error: inspect(error)
        })

        error
    end
  end

  # Enriches the normalized killmail data
  @spec enrich_killmail_data(killmail()) :: result()
  defp enrich_killmail_data(killmail) do
    # Reuse the existing enrichment logic for now
    # This maintains compatibility during the transition
    enriched = Enrichment.enrich_killmail_data(killmail)

    # Return the enriched killmail with tracking metadata
    metadata = Map.get(enriched, :metadata, %{})
    {:ok, Map.put_new(enriched, :metadata, metadata)}
  rescue
    error ->
      stacktrace = __STACKTRACE__
      log_killmail_error(killmail, nil, {error, stacktrace})
      {:error, :enrichment_failed}
  end

  # Validates the normalized killmail data
  @spec validate_killmail_data(killmail()) :: result()
  defp validate_killmail_data(killmail) do
    # Ensure internal data consistency first
    killmail = ensure_data_consistency(killmail)

    # Validate without trying to fix issues
    case Validator.validate_complete_data(killmail) do
      :ok ->
        # Validation passed
        AppLogger.kill_info("Killmail passed validation", %{
          killmail_id: killmail.killmail_id
        })

        {:ok, killmail}

      {:error, reasons} ->
        # Log the validation failure
        log_validation_failure(killmail, reasons)

        # Return error without trying to fix
        {:error, {:enrichment_validation_failed, reasons}}
    end
  end

  # Persists the normalized killmail to database
  @spec persist_normalized_killmail(killmail(), Context.t()) :: result()
  defp persist_normalized_killmail(killmail, ctx) do
    # Check if we should even try to persist based on notification rules
    case KillDeterminer.should_notify?(killmail) do
      {:ok, %{should_notify: false, reason: reason}} when is_binary(reason) ->
        # Check if this is a "not tracked" case inside the function body
        not_tracked =
          String.contains?(reason, "Not tracked by any character") or
            reason == "Not tracked by any character or system"

        if not_tracked do
          # Don't even attempt to persist if not tracked
          AppLogger.kill_info("[Pipeline] Skipping persistence - not tracked", %{
            kill_id: killmail.killmail_id,
            reason: reason
          })

          # Mark as not persisted
          {:ok, Map.put(killmail, :persisted, false)}
        else
          # Normal persistence path for other reasons
          persist_if_database_available(killmail, ctx)
        end

      _ ->
        # Normal persistence path
        persist_if_database_available(killmail, ctx)
    end
  end

  # Handle persistence based on database availability
  defp persist_if_database_available(killmail, ctx) do
    AppLogger.kill_info("[Pipeline] Persisting normalized killmail", %{
      kill_id: killmail.killmail_id,
      character_id: ctx.character_id
    })

    # Check if database is available first
    if database_available?() do
      # Database is available, proceed with persistence
      do_persist_normalized_killmail(killmail, ctx)
    else
      # Database unavailable, but still allow notifications
      AppLogger.kill_info("[Pipeline] Database unavailable, skipping persistence", %{
        kill_id: killmail.killmail_id
      })

      # Return killmail with persisted=false flag
      {:ok, Map.put(killmail, :persisted, false)}
    end
  end

  # Check if the database is available
  defp database_available? do
    # Check if Repo process exists and is alive
    case Process.whereis(WandererNotifier.Data.Repo) do
      pid when is_pid(pid) -> Process.alive?(pid)
      _ -> false
    end
  rescue
    _ -> false
  end

  # Actual database persistence function
  defp do_persist_normalized_killmail(killmail, ctx) do
    case KillmailPersistence.maybe_persist_normalized_killmail(killmail, ctx.character_id) do
      {:ok, :persisted} ->
        AppLogger.kill_info("[Pipeline] Normalized killmail was newly persisted", %{
          kill_id: killmail.killmail_id,
          character_id: ctx.character_id
        })

        Metrics.track_persistence(ctx)
        {:ok, killmail}

      {:ok, :already_exists} ->
        AppLogger.kill_info("[Pipeline] Normalized killmail already existed", %{
          kill_id: killmail.killmail_id
        })

        {:ok, killmail}

      # Successfully saved to database and returned the record
      {:ok, record} when is_struct(record) ->
        AppLogger.kill_info("[Pipeline] Normalized killmail was persisted to database", %{
          kill_id: killmail.killmail_id,
          character_id: ctx.character_id,
          record_id: Map.get(record, :id, "unknown")
        })

        Metrics.track_persistence(ctx)
        {:ok, killmail}

      :ignored ->
        AppLogger.kill_info("[Pipeline] Normalized killmail persistence was ignored", %{
          kill_id: killmail.killmail_id,
          reason: "Not tracked by any character"
        })

        {:ok, killmail}

      error ->
        AppLogger.kill_error("[Pipeline] Normalized killmail persistence failed", %{
          kill_id: killmail.killmail_id,
          error: inspect(error)
        })

        # Return original killmail with error so notifications can still process
        {:ok, killmail}
    end
  rescue
    e ->
      AppLogger.kill_error("[Pipeline] Exception during killmail persistence", %{
        kill_id: killmail.killmail_id,
        error: Exception.message(e)
      })

      # Continue processing for notifications despite persistence error
      {:ok, killmail}
  end

  @spec check_notification(killmail(), Context.t()) :: {:ok, boolean(), String.t()}
  defp check_notification(killmail, ctx) do
    # Log the killmail structure for debugging
    log_killmail_structure(killmail, ctx)

    # Only send notifications for realtime processing
    case KillDeterminer.should_notify?(killmail) do
      {:ok, %{should_notify: should_notify, reason: reason}} ->
        process_notification_decision(killmail, ctx, should_notify, reason)

      {:error, reason} ->
        handle_notification_error(killmail, reason)

      unexpected ->
        handle_unexpected_result(killmail, unexpected)
    end
  end

  # Log killmail structure details
  defp log_killmail_structure(killmail, ctx) do
    AppLogger.kill_info("Checking notification status for killmail", %{
      kill_id: get_kill_id(killmail),
      killmail_keys: Map.keys(killmail),
      has_esi_data: Map.has_key?(killmail, :esi_data),
      esi_data_present:
        if(Map.has_key?(killmail, :esi_data), do: !is_nil(killmail.esi_data), else: false),
      mode: ctx && ctx.mode && ctx.mode.mode
    })
  end

  # Process the notification decision
  defp process_notification_decision(killmail, ctx, should_notify, reason) do
    # Only notify if in realtime mode
    real_should_notify = Context.realtime?(ctx) and should_notify

    # Update killmail based on notification decision
    updated_killmail = update_killmail_persistence_flag(killmail, reason)

    # Log the decision
    AppLogger.kill_info("Notification decision", %{
      should_notify: real_should_notify,
      reason: reason,
      realtime: Context.realtime?(ctx)
    })

    # Return the updated killmail by using process_flag to pass it back to the caller
    Process.put(:last_killmail_update, updated_killmail)
    {:ok, real_should_notify, reason}
  end

  # Update killmail persistence flag if needed
  defp update_killmail_persistence_flag(killmail, reason) when is_binary(reason) do
    not_tracked = not_tracked_reason?(reason)

    if not_tracked do
      # Ensure we mark as not persisted for clear logging
      Map.put(killmail, :persisted, false)
    else
      # Keep existing persisted status
      killmail
    end
  end

  defp update_killmail_persistence_flag(killmail, _reason) do
    # Non-string reason, keep existing persisted status
    killmail
  end

  # Check if reason indicates not tracked
  defp not_tracked_reason?(reason) do
    String.contains?(reason, "Not tracked by any character") or
      reason == "Not tracked by any character or system"
  end

  # Handle notification error case
  defp handle_notification_error(killmail, reason) do
    # Handle error case by not sending notification and logging the issue
    AppLogger.kill_error("Error determining notification status", %{
      killmail_id: killmail.killmail_id,
      error: inspect(reason)
    })

    # Return with notification disabled and error as reason
    {:ok, false, "Error determining notification eligibility"}
  end

  # Handle unexpected result
  defp handle_unexpected_result(killmail, unexpected) do
    # Catch any unexpected return values and log them
    AppLogger.kill_error("Unexpected result from notification determiner", %{
      killmail_id: killmail.killmail_id,
      result: inspect(unexpected)
    })

    # Return with notification disabled
    {:ok, false, "Unexpected notification determination result"}
  end

  @spec maybe_send_notification(killmail(), boolean(), Context.t()) :: result()
  defp maybe_send_notification(killmail, true, ctx) do
    case Notification.send_kill_notification(killmail, killmail.killmail_id) do
      {:ok, _} ->
        Metrics.track_notification_sent(ctx)
        {:ok, killmail}

      # Instead of returning the raw error, transform it
      error ->
        # Log the error but don't let it propagate
        AppLogger.kill_info("Failed to send notification", %{
          killmail_id: killmail.killmail_id,
          error: inspect(error)
        })

        # Always return success with the original killmail
        # This prevents errors from notification from breaking the pipeline
        {:ok, killmail}
    end
  end

  defp maybe_send_notification(killmail, false, _ctx) do
    {:ok, killmail}
  end

  # Logging helpers

  defp log_killmail_outcome(killmail, ctx,
         persisted: persisted,
         notified: notified,
         reason: reason
       ) do
    kill_id = get_kill_id(killmail)
    kill_time = Map.get(killmail, "killmail_time")

    # Check for persisted flag in killmail that might override the parameter
    persisted =
      if is_map(killmail) && Map.has_key?(killmail, :persisted),
        do: Map.get(killmail, :persisted),
        else: persisted

    metadata = %{
      kill_id: kill_id,
      kill_time: kill_time,
      character_id: ctx && ctx.character_id,
      character_name: ctx && ctx.character_name,
      batch_id: ctx && ctx.batch_id,
      reason: reason,
      processing_mode: ctx && ctx.mode && ctx.mode.mode
    }

    # Determine status and message based on outcomes
    {message, status} = get_log_details(persisted, notified, reason)

    # Add status to metadata and log with appropriate level
    updated_metadata = Map.put(metadata, :status, status)

    # Most individual killmail logs should be debug level
    # Only keep "saved_and_notified" at info level
    if status == "saved_and_notified" do
      AppLogger.kill_info(message, updated_metadata)
    else
      # All other statuses (skipped, duplicate, saved without notification) should be debug
      AppLogger.kill_info(message, updated_metadata)
    end
  end

  # Helper function to get log message and status based on outcomes
  defp get_log_details(persisted, notified, reason) do
    cond do
      # First check for successful save and notify
      persisted == true and notified == true ->
        get_save_notify_details()

      # Check for duplicates
      persisted == true and notified == false and reason == "Duplicate kill" ->
        get_duplicate_details()

      # Check for not tracked killmails
      is_binary(reason) and not_tracked_reason?(reason) ->
        get_not_tracked_details()

      # Normal saved without notification
      persisted == true and notified == false ->
        get_saved_without_notify_details()

      # Everything else is skipped
      persisted == false and notified == false ->
        get_skipped_details()

      # Catch-all for unexpected combinations
      true ->
        get_unknown_details()
    end
  end

  # Individual helper functions for each outcome type
  defp get_save_notify_details, do: {"Killmail saved and notified", "saved_and_notified"}
  defp get_duplicate_details, do: {"Killmail already exists", "duplicate"}
  defp get_not_tracked_details, do: {"Killmail processing skipped - not tracked", "skipped"}
  defp get_saved_without_notify_details, do: {"Killmail saved without notification", "saved"}
  defp get_skipped_details, do: {"Killmail processing skipped", "skipped"}
  defp get_unknown_details, do: {"Killmail processing outcome unknown", "unknown"}

  defp log_killmail_error(killmail, ctx, error) do
    kill_id = get_kill_id(killmail)
    kill_time = Map.get(killmail, "killmail_time")

    # Safely extract context values with default fallbacks
    character_id = ctx && ctx.character_id
    character_name = (ctx && ctx.character_name) || "unknown"
    batch_id = (ctx && ctx.batch_id) || "unknown"
    processing_mode = ctx && ctx.mode && ctx.mode.mode

    # Create base metadata
    metadata = %{
      kill_id: kill_id,
      kill_time: kill_time,
      character_id: character_id,
      character_name: character_name,
      batch_id: batch_id,
      status: "error",
      processing_mode: processing_mode
    }

    # Format error information based on error type
    error_info = format_error_info(error)

    # Log the error with formatted information
    AppLogger.kill_error(
      "Killmail processing failed",
      Map.merge(metadata, error_info)
    )
  end

  # Helper to format error information based on error type
  defp format_error_info({exception, stacktrace}) when is_list(stacktrace) do
    %{
      error: Exception.message(exception),
      stacktrace: Exception.format_stacktrace(stacktrace)
    }
  end

  defp format_error_info(error) do
    %{error: inspect(error)}
  end

  defp get_kill_id(data), do: Extractor.get_killmail_id(data)

  # Validate that the enriched data meets requirements (now used in validate_killmail_data)
  # This comment explains why we removed the duplicate function

  defp log_validation_failure(killmail, reasons) do
    debug_data = Extractor.debug_data(killmail)

    victim_status = if debug_data.has_victim_data, do: "present", else: "missing"
    victim_ship = if debug_data.has_victim_data, do: "present", else: "missing"

    AppLogger.kill_error(
      "Enriched killmail failed validation - " <>
        "killmail_id: #{Extractor.get_killmail_id(killmail)}, " <>
        "failures: #{reasons}, " <>
        "system_name: #{debug_data.system_name}, " <>
        "system_id: #{inspect(debug_data.system_id)}, " <>
        "has_victim: #{debug_data.has_victim_data}, " <>
        "victim_name: #{victim_status}, " <>
        "victim_ship: #{victim_ship}, " <>
        "attackers_count: #{debug_data.attacker_count}"
    )
  end

  # Ensure data consistency by copying enriched data throughout the struct
  defp ensure_data_consistency(killmail) do
    # Extract needed data from esi_data
    esi_data = killmail.esi_data || %{}

    # Get essential fields with proper type conversion
    system_id = get_and_convert_system_id(esi_data)
    system_name = Map.get(esi_data, "solar_system_name")

    # Ensure kill_time is present and properly formatted
    kill_time = get_and_convert_kill_time(esi_data, killmail)

    # Create a consistent esi_data map
    updated_esi_data =
      esi_data
      |> Map.put("solar_system_id", system_id)
      |> Map.put("solar_system_name", system_name)
      |> Map.put("killmail_time", format_kill_time(kill_time))

    # Update the killmail with all consistent values
    Map.merge(killmail, %{
      esi_data: updated_esi_data,
      solar_system_id: system_id,
      solar_system_name: system_name,
      kill_time: kill_time
    })
  end

  # Convert system_id to integer consistently
  defp get_and_convert_system_id(esi_data) do
    system_id = Map.get(esi_data, "solar_system_id")

    cond do
      is_integer(system_id) ->
        system_id

      is_binary(system_id) ->
        case Integer.parse(system_id) do
          {id, _} -> id
          :error -> nil
        end

      true ->
        nil
    end
  end

  # Get and convert kill_time to DateTime consistently
  defp get_and_convert_kill_time(esi_data, killmail) do
    # Try to get from ESI data first, then killmail directly
    killmail_time =
      Map.get(esi_data, "killmail_time") ||
        Map.get(killmail, :kill_time) ||
        Map.get(killmail, "kill_time")

    cond do
      is_struct(killmail_time, DateTime) ->
        killmail_time

      is_binary(killmail_time) ->
        case DateTime.from_iso8601(killmail_time) do
          {:ok, datetime, _} -> datetime
          _ -> DateTime.utc_now()
        end

      true ->
        DateTime.utc_now()
    end
  end

  # Format kill_time for storage in esi_data
  defp format_kill_time(kill_time) do
    cond do
      is_binary(kill_time) -> kill_time
      is_struct(kill_time, DateTime) -> DateTime.to_iso8601(kill_time)
      true -> DateTime.to_iso8601(DateTime.utc_now())
    end
  end
end
