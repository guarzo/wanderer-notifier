defmodule WandererNotifier.KillmailProcessing.Pipeline do
  @moduledoc """
  Pipeline for processing killmail data from start to finish.
  Handles tasks like enrichment, validation, persistence, and notifications.
  """

  alias WandererNotifier.Api.ESI.Service, as: ESIService
  alias WandererNotifier.Core.Stats
  alias WandererNotifier.KillmailProcessing.{Context, Extractor, KillmailData, Metrics, Transformer, Validator}
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

        # Extract available information
        kill_id = get_kill_id(zkb_data)

        # Create a meaningful error message
        AppLogger.kill_info("Error processing killmail ##{kill_id}", %{
          error: inspect(error),
          kill_id: kill_id,
          status: "failed"
        })

        # Return the error for proper handling
        error
    end
  end

  @doc """
  Process a pre-created KillmailData struct through the pipeline.
  Skips the initial creation step and starts from enrichment.
  Useful for debug tools and testing.

  ## Parameters
    - killmail: A KillmailData struct to process
    - ctx: Processing context

  ## Returns
    - {:ok, result} on success
    - {:error, reason} on failure
  """
  @spec process_killmail_with_data(KillmailData.t(), Context.t()) :: result()
  def process_killmail_with_data(%KillmailData{} = killmail, ctx) do
    Metrics.track_processing_start(ctx)

    AppLogger.kill_info("Processing pre-created killmail data", %{
      kill_id: killmail.killmail_id,
      source: ctx.source,
      mode: (ctx.mode && ctx.mode.mode) || :unknown
    })

    # Check if debug force notification is enabled
    should_force_notify = ctx.metadata && Map.get(ctx.metadata, :force_notification, false)

    with {:ok, enriched} <- enrich_killmail_data(killmail),
         {:ok, validated_killmail} <- validate_killmail_data(enriched),
         {:ok, persisted} <- persist_normalized_killmail(validated_killmail, ctx),
         {:ok, should_notify, reason} <-
           check_notification_with_override(persisted, ctx, should_force_notify),
         {:ok, result} <- maybe_send_notification(persisted, should_notify, ctx) do
      # Successfully processed killmail
      Metrics.track_processing_complete(ctx, {:ok, result})

      # Cleanup and get final state
      final_killmail = Process.get(:last_killmail_update) || result
      Process.delete(:last_killmail_update)

      # Get persistence status
      was_persisted =
        if is_map(final_killmail) && Map.has_key?(final_killmail, :persisted),
          do: Map.get(final_killmail, :persisted),
          else: true

      # Log outcome with override info if applicable
      override_info = if should_force_notify, do: " (notification forced)", else: ""

      log_killmail_outcome(final_killmail, ctx,
        persisted: was_persisted,
        notified: should_notify,
        reason: "#{reason}#{override_info}"
      )

      {:ok, final_killmail}
    else
      # Handle errors same as process_killmail
      {:error, {:skipped, reason}} ->
        Metrics.track_processing_skipped(ctx)
        log_killmail_outcome(killmail, ctx, persisted: false, notified: false, reason: reason)
        {:ok, :skipped}

      error ->
        Metrics.track_processing_error(ctx)

        # Get the killmail ID
        kill_id = get_kill_id(killmail)

        # Extract system and victim information based on type
        {system_name, victim_name, victim_ship} = extract_killmail_display_info(killmail)

        AppLogger.kill_info(
          "❌ Error processing killmail ##{kill_id}: #{victim_name} (#{victim_ship}) in #{system_name}",
          %{
            kill_id: kill_id,
            system_name: system_name,
            victim_name: victim_name,
            victim_ship: victim_ship,
            error: inspect(error)
          }
        )

        error
    end
  end

  # Creates a normalized killmail from the zKillboard data
  @spec create_normalized_killmail(map()) :: result()
  defp create_normalized_killmail(zkb_data) do
    kill_id = Map.get(zkb_data, "killmail_id")
    hash = get_in(zkb_data, ["zkb", "hash"])

    case ESIService.get_killmail(kill_id, hash) do
      {:ok, esi_data} ->
        # Use KillmailData.from_zkb_and_esi to create structured data
        {:ok, KillmailData.from_zkb_and_esi(zkb_data, esi_data)}

      {:error, :not_found} ->
        # Log at debug level to reduce noise - this happens often for new kills
        AppLogger.kill_info("ESI data not found for killmail", %{
          kill_id: kill_id,
          hash: hash
        })

        {:error, {:skipped, "ESI data not available"}}

      error ->
        AppLogger.kill_error("Error fetching killmail from ESI", %{
          kill_id: kill_id,
          error: inspect(error)
        })

        error
    end
  end

  # Enriches the normalized killmail data
  @spec enrich_killmail_data(killmail()) :: result()
  defp enrich_killmail_data(killmail) do
    # Add detailed logging before enrichment
    log_enrichment_input(killmail)

    # Reuse the existing enrichment logic for now
    # This maintains compatibility during the transition
    enriched = Enrichment.enrich_killmail_data(killmail)

    # Add detailed logging after enrichment
    log_enrichment_output(enriched)

    # Return the enriched killmail with tracking metadata
    metadata = Map.get(enriched, :metadata, %{})
    {:ok, Map.put_new(enriched, :metadata, metadata)}
  rescue
    error ->
      stacktrace = __STACKTRACE__
      log_killmail_error(killmail, nil, {error, stacktrace})
      {:error, :enrichment_failed}
  end

  # Log details about the killmail before enrichment
  defp log_enrichment_input(killmail) do
    # Get basic identifiers
    kill_id = Extractor.get_killmail_id(killmail)

    # Get victim data
    victim = Extractor.get_victim(killmail) || %{}
    victim_name = Map.get(victim, "character_name") || "Unknown Pilot"
    victim_ship = Map.get(victim, "ship_type_name") || "Unknown Ship"

    # Get system name
    system_name = Extractor.get_system_name(killmail) || "Unknown System"

    # Use simple string message
    AppLogger.kill_debug("PRE-ENRICHMENT Kill ##{kill_id}: #{victim_name} (#{victim_ship}) in #{system_name}")
  end

  # Log details about the killmail after enrichment
  defp log_enrichment_output(killmail) do
    # Get basic identifiers
    kill_id = Extractor.get_killmail_id(killmail)

    # Get victim data
    victim = Extractor.get_victim(killmail) || %{}
    victim_name = Map.get(victim, "character_name") || "Unknown Pilot"
    victim_ship = Map.get(victim, "ship_type_name") || "Unknown Ship"
    victim_id = Map.get(victim, "character_id")

    # Get system name
    system_name = Extractor.get_system_name(killmail) || "Unknown System"

    # Use simple string message
    AppLogger.kill_debug("POST-ENRICHMENT Kill ##{kill_id}: #{victim_name} (#{victim_ship}) in #{system_name}, Victim ID: #{victim_id || "unknown"}")
  end

  # Validates the normalized killmail data
  @spec validate_killmail_data(killmail()) :: result()
  defp validate_killmail_data(killmail) do
    # Ensure internal data consistency first
    killmail = ensure_data_consistency(killmail)

    # Validate without trying to fix issues
    case Validator.validate_complete_data(killmail) do
      :ok ->
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
          AppLogger.kill_debug("[Pipeline] Skipping persistence - not tracked", %{
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
    AppLogger.kill_debug("[Pipeline] Persisting normalized killmail", %{
      kill_id: killmail.killmail_id,
      character_id: ctx.character_id
    })

    # Check if database is available first
    if database_available?() do
      # Database is available, proceed with persistence
      do_persist_normalized_killmail(killmail, ctx)
    else
      # Database unavailable, but still allow notifications
      AppLogger.kill_debug("[Pipeline] Database unavailable, skipping persistence", %{
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
    # Convert to standardized format using Transformer for consistency
    standardized_killmail = Transformer.to_killmail_data(killmail)

    case KillmailPersistence.maybe_persist_normalized_killmail(standardized_killmail, ctx.character_id) do
      {:ok, :persisted} ->
        AppLogger.kill_debug("[Pipeline] Normalized killmail was newly persisted", %{
          kill_id: standardized_killmail.killmail_id,
          character_id: ctx.character_id
        })

        Metrics.track_persistence(ctx)
        {:ok, standardized_killmail}

      {:ok, :already_exists} ->
        AppLogger.kill_debug("[Pipeline] Normalized killmail already existed", %{
          kill_id: standardized_killmail.killmail_id
        })

        {:ok, standardized_killmail}

      # Successfully saved to database and returned the record
      {:ok, record} when is_struct(record) ->
        AppLogger.kill_debug("[Pipeline] Normalized killmail was persisted to database", %{
          kill_id: standardized_killmail.killmail_id,
          character_id: ctx.character_id,
          record_id: Map.get(record, :id, "unknown")
        })

        Metrics.track_persistence(ctx)
        {:ok, standardized_killmail}

      :ignored ->
        AppLogger.kill_debug("[Pipeline] Normalized killmail persistence was ignored", %{
          kill_id: standardized_killmail.killmail_id,
          reason: "Not tracked by any character"
        })

        {:ok, standardized_killmail}

      error ->
        AppLogger.kill_error("[Pipeline] Normalized killmail persistence failed", %{
          kill_id: standardized_killmail.killmail_id,
          error: inspect(error)
        })

        # Return original killmail with error so notifications can still process
        {:ok, standardized_killmail}
    end
  rescue
    e ->
      AppLogger.kill_error("[Pipeline] Exception during killmail persistence", %{
        kill_id: Extractor.get_killmail_id(killmail),
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
    kill_id = get_kill_id(killmail)

    struct_type = cond do
      is_struct(killmail) ->
        module_name = killmail.__struct__
        "#{module_name}"
      true ->
        "Not a struct"
    end

    top_level_keys = if is_map(killmail), do: Map.keys(killmail), else: []

    AppLogger.kill_debug("Checking notification status for killmail", %{
      kill_id: kill_id,
      struct_type: struct_type,
      killmail_keys: top_level_keys,
      has_esi_data: Map.has_key?(killmail, :esi_data),
      esi_data_present:
        if(Map.has_key?(killmail, :esi_data), do: !is_nil(killmail.esi_data), else: false),
      victim_name: if(is_map(killmail), do: Map.get(killmail, :victim_name), else: nil),
      system_name: if(is_map(killmail), do: Map.get(killmail, :solar_system_name), else: nil),
      system_security: if(is_map(killmail), do: Map.get(killmail, :solar_system_security), else: nil),
      mode: ctx && ctx.mode && ctx.mode.mode
    })
  end

  # Process the notification decision
  defp process_notification_decision(killmail, ctx, should_notify, reason) do
    # Only notify if in realtime mode
    real_should_notify = Context.realtime?(ctx) and should_notify

    # Update killmail based on notification decision
    updated_killmail = update_killmail_persistence_flag(killmail, reason)

    # Log the decision at debug level to reduce duplicate messages
    AppLogger.kill_debug("Notification decision", %{
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
    kill_id = get_kill_id(killmail)

    # Add detailed error information
    case Notification.send_kill_notification(killmail, kill_id) do
      {:ok, _} ->
        Metrics.track_notification_sent(ctx)
        {:ok, killmail}

      # Instead of returning the raw error, transform it
      error ->
        # Extract system and victim information based on type
        {system_name, victim_name, victim_ship} = extract_killmail_display_info(killmail)

        # Log the error but don't let it propagate
        AppLogger.kill_error(
          "❌ Failed to send notification for Kill ##{kill_id}: #{victim_name} (#{victim_ship}) in #{system_name}",
          %{
            killmail_id: kill_id,
            victim_name: victim_name,
            system_name: system_name,
            victim_ship: victim_ship,
            error: inspect(error)
          }
        )

        # Always return success with the original killmail
        # This prevents errors from notification from breaking the pipeline
        {:ok, killmail}
    end
  end

  defp maybe_send_notification(killmail, false, _ctx) do
    {:ok, killmail}
  end

  # Logging helpers

  defp log_killmail_outcome(killmail, _ctx,
         persisted: persisted,
         notified: notified,
         reason: reason
       ) do
    # Get basic data
    kill_id = get_kill_id(killmail)

    # Extract display information
    {victim_name, victim_ship, system_name} = extract_display_info(killmail)

    # Format the log message components
    status_emoji = get_status_emoji(notified)
    persistence_status = get_persistence_status(persisted)
    short_reason = create_short_reason(reason)

    # Log a simplified, direct string message with emoji
    AppLogger.kill_info("#{status_emoji} ##{kill_id}: #{victim_name} (#{victim_ship}) in #{system_name}#{persistence_status} - #{short_reason}")
  end

  # Helper to extract display information from the killmail
  defp extract_display_info(killmail) do
    # Get values directly from the killmail struct where possible
    victim_name = Map.get(killmail, :victim_name) || "Unknown Pilot"
    victim_ship = Map.get(killmail, :victim_ship_name) || "Unknown Ship"
    system_name = Map.get(killmail, :solar_system_name) || "Unknown System"

    {victim_name, victim_ship, system_name}
  end

  # Helper to get the status emoji based on notification status
  defp get_status_emoji(true), do: "✉️"
  defp get_status_emoji(false), do: "⏭️"

  # Helper to get the persistence status text
  defp get_persistence_status(true), do: ""
  defp get_persistence_status(false), do: " (not saved)"

  # Helper to create a shortened reason that's more readable
  defp create_short_reason(reason) do
    cond do
      String.contains?(reason, "Not tracked") -> "Not tracked"
      String.contains?(reason, "Duplicate") -> "Duplicate"
      true -> reason
    end
  end

  defp log_killmail_error(killmail, ctx, error) do
    # Get the killmail ID
    kill_id = get_kill_id(killmail)

    # Extract system and victim information based on type
    {system_name, victim_name, victim_ship} = extract_killmail_display_info(killmail)

    # Safely extract context values with default fallbacks
    character_id = ctx && ctx.character_id
    character_name = (ctx && ctx.character_name) || "unknown"

    # Format error information
    error_info = format_error_info(error)

    # Build a clear error message
    message = "❌ Kill ##{kill_id}: #{victim_name} (#{victim_ship}) in #{system_name} | Processing error"

    # Create metadata with all relevant information
    metadata = %{
      kill_id: kill_id,
      system_name: system_name,
      victim_name: victim_name,
      victim_ship: victim_ship,
      character_id: character_id,
      character_name: character_name,
      status: "error"
    }

    # Add error details to metadata
    full_metadata = Map.merge(metadata, error_info)

    # Log at error level
    AppLogger.kill_error(message, full_metadata)
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
    # Convert to standardized KillmailData format first to ensure consistent access
    killmail_data = Transformer.to_killmail_data(killmail)

    # Extract needed data using Extractor for consistency
    system_id = Extractor.get_system_id(killmail_data)
    system_name = Extractor.get_system_name(killmail_data)
    kill_time = Extractor.get_kill_time(killmail_data)

    # Get the esi_data field
    esi_data = Map.get(killmail_data, :esi_data) || %{}

    # Create a consistent esi_data map
    updated_esi_data =
      esi_data
      |> Map.put("solar_system_id", system_id)
      |> Map.put("solar_system_name", system_name)
      |> Map.put("killmail_time", format_kill_time(kill_time))

    # Update the killmail with all consistent values
    Map.merge(killmail_data, %{
      esi_data: updated_esi_data,
      solar_system_id: system_id,
      solar_system_name: system_name,
      kill_time: kill_time
    })
  end

  # Format kill_time for storage in esi_data
  defp format_kill_time(kill_time) do
    cond do
      is_binary(kill_time) -> kill_time
      is_struct(kill_time, DateTime) -> DateTime.to_iso8601(kill_time)
      true -> DateTime.to_iso8601(DateTime.utc_now())
    end
  end

  # Check notification status with optional override for debug/testing
  defp check_notification_with_override(killmail, ctx, force_notify) do
    # First do normal notification check
    case KillDeterminer.should_notify?(killmail) do
      {:ok, %{should_notify: should_notify, reason: reason}} ->
        if force_notify do
          # Override with forced notification
          AppLogger.kill_info("FORCED NOTIFICATION: Overriding normal notification decision", %{
            kill_id: get_kill_id(killmail),
            original_should_notify: should_notify,
            original_reason: reason,
            forced: true
          })

          # Return forced notification with original reason
          process_notification_decision(killmail, ctx, true, "#{reason} (forced notification)")
        else
          # Normal processing
          process_notification_decision(killmail, ctx, should_notify, reason)
        end

      {:error, reason} ->
        if force_notify do
          # Force notification despite error
          AppLogger.kill_info("FORCED NOTIFICATION: Overriding error", %{
            kill_id: get_kill_id(killmail),
            original_error: inspect(reason),
            forced: true
          })

          # Return forced notification
          process_notification_decision(killmail, ctx, true, "Forced notification despite error")
        else
          # Normal error handling
          handle_notification_error(killmail, reason)
        end

      unexpected ->
        if force_notify do
          # Force notification despite unexpected result
          AppLogger.kill_info("FORCED NOTIFICATION: Overriding unexpected result", %{
            kill_id: get_kill_id(killmail),
            original_result: inspect(unexpected),
            forced: true
          })

          # Return forced notification
          process_notification_decision(
            killmail,
            ctx,
            true,
            "Forced notification despite unexpected result"
          )
        else
          # Normal unexpected handling
          handle_unexpected_result(killmail, unexpected)
        end
    end
  end

  # Extract system and victim information for logging
  defp extract_killmail_display_info(%WandererNotifier.Resources.Killmail{} = killmail) do
    # KillmailResource has direct fields for these values
    {
      killmail.solar_system_name || "Unknown System",
      killmail.victim_name || "Unknown Pilot",
      killmail.victim_ship_name || "Unknown Ship"
    }
  end

  defp extract_killmail_display_info(killmail) do
    # First check if the data is directly in the top-level fields
    victim_name = Map.get(killmail, :victim_name)
    victim_ship = Map.get(killmail, :victim_ship_name)
    system_name = Map.get(killmail, :solar_system_name)

    if victim_name && victim_ship && system_name do
      # Use top-level fields if they exist
      {system_name, victim_name, victim_ship}
    else
      # Fall back to using the Extractor for older formats
      victim = Extractor.get_victim(killmail) || %{}
      {
        Extractor.get_system_name(killmail) || "Unknown System",
        Map.get(victim, "character_name") || "Unknown Pilot",
        Map.get(victim, "ship_type_name") || "Unknown Ship"
      }
    end
  end

end
