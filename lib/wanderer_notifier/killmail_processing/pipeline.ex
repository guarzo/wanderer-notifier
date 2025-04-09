defmodule WandererNotifier.KillmailProcessing.Pipeline do
  @moduledoc """
  Pipeline for processing killmail data from start to finish.
  Handles tasks like enrichment, validation, persistence, and notifications.
  """

  alias WandererNotifier.Api.ESI.Service, as: ESIService
  alias WandererNotifier.Core.Stats
  alias WandererNotifier.Data.KillmailEnrichment, as: Enrichment
  alias WandererNotifier.Killmail
  alias WandererNotifier.Killmail.Validation, as: KillmailValidation
  alias WandererNotifier.KillmailProcessing.{Context, Metrics}
  alias WandererNotifier.Logger.Logger, as: AppLogger
  alias WandererNotifier.Notifications.Determiner.Kill, as: KillDeterminer
  alias WandererNotifier.Processing.Killmail.{Enrichment, Notification}
  alias WandererNotifier.Resources.Killmail, as: KillmailResource
  alias WandererNotifier.Resources.KillmailPersistence

  @type killmail :: KillmailResource.t()
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
      Metrics.track_processing_complete(ctx, {:ok, result})
      log_killmail_outcome(result, ctx, persisted: true, notified: should_notify, reason: reason)
      {:ok, result}
    else
      {:error, {:skipped, reason}} ->
        Metrics.track_processing_skipped(ctx)
        log_killmail_outcome(zkb_data, ctx, persisted: false, notified: false, reason: reason)
        {:ok, :skipped}

      {:error, {:enrichment_validation_failed, reasons}} ->
        AppLogger.kill_error("Killmail enrichment validation failed", %{
          reasons: reasons,
          killmail_id: zkb_data["killmail_id"] || "unknown"
        })

        Metrics.track_processing_error(ctx)
        {:error, :enrichment_validation_failed}

      error ->
        Metrics.track_processing_error(ctx)
        log_killmail_error(zkb_data, ctx, error)
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
        # Create normalized model directly
        {:ok,
         %{
           killmail_id: kill_id,
           zkb_data: Map.get(zkb_data, "zkb", %{}),
           esi_data: esi_data
         }}

      error ->
        log_killmail_error(zkb_data, nil, error)
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
    # Currently reuse the existing validation logic
    # This will be updated to use WandererNotifier.Killmail.Validation module
    # once fully migrated
    validate_enriched_data(killmail)
  end

  # Persists the normalized killmail to database
  @spec persist_normalized_killmail(killmail(), Context.t()) :: result()
  defp persist_normalized_killmail(killmail, ctx) do
    AppLogger.kill_debug("[Pipeline] Persisting normalized killmail", %{
      kill_id: killmail.killmail_id,
      character_id: ctx.character_id
    })

    # Use the new KillmailPersistence.maybe_persist_normalized_killmail
    # that works with the normalized model
    case KillmailPersistence.maybe_persist_normalized_killmail(killmail, ctx.character_id) do
      {:ok, :persisted} ->
        AppLogger.kill_debug("[Pipeline] Normalized killmail was newly persisted", %{
          kill_id: killmail.killmail_id,
          character_id: ctx.character_id
        })

        Metrics.track_persistence(ctx)
        {:ok, killmail}

      {:ok, :already_exists} ->
        AppLogger.kill_debug("[Pipeline] Normalized killmail already existed", %{
          kill_id: killmail.killmail_id
        })

        {:ok, killmail}

      # Successfully saved to database and returned the record
      {:ok, record} when is_struct(record) ->
        AppLogger.kill_debug("[Pipeline] Normalized killmail was persisted to database", %{
          kill_id: killmail.killmail_id,
          character_id: ctx.character_id,
          record_id: Map.get(record, :id, "unknown")
        })

        Metrics.track_persistence(ctx)
        {:ok, killmail}

      :ignored ->
        AppLogger.kill_debug("[Pipeline] Normalized killmail persistence was ignored", %{
          kill_id: killmail.killmail_id,
          reason: "Not tracked by any character"
        })

        {:ok, killmail}

      error ->
        AppLogger.kill_error("[Pipeline] Normalized killmail persistence failed", %{
          kill_id: killmail.killmail_id,
          error: inspect(error)
        })

        error
    end
  end

  @spec check_notification(killmail(), Context.t()) :: {:ok, boolean(), String.t()}
  defp check_notification(killmail, ctx) do
    # Only send notifications for realtime processing
    case KillDeterminer.should_notify?(killmail) do
      {:ok, %{should_notify: should_notify, reason: reason}} ->
        should_notify = Context.realtime?(ctx) and should_notify
        {:ok, should_notify, reason}

      error ->
        error
    end
  end

  @spec maybe_send_notification(killmail(), boolean(), Context.t()) :: result()
  defp maybe_send_notification(killmail, true, ctx) do
    case Notification.send_kill_notification(killmail, killmail.killmail_id) do
      {:ok, _} ->
        Metrics.track_notification_sent(ctx)
        {:ok, killmail}

      error ->
        log_killmail_error(killmail, ctx, error)
        error
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
      AppLogger.kill_debug(message, updated_metadata)
    end
  end

  # Helper function to get log message and status based on outcomes
  defp get_log_details(persisted, notified, reason) do
    case {persisted, notified, reason} do
      {true, true, _} ->
        {"Killmail saved and notified", "saved_and_notified"}

      {true, false, "Duplicate kill"} ->
        {"Killmail already exists", "duplicate"}

      {true, false, _} ->
        {"Killmail saved without notification", "saved"}

      {false, false, _} ->
        {"Killmail processing skipped", "skipped"}
    end
  end

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

  defp get_kill_id(%{killmail_id: id}), do: id

  defp get_kill_id(data) do
    AppLogger.kill_error("Failed to extract kill_id", %{
      data: inspect(data)
    })

    nil
  end

  # Validate that the enriched data meets requirements
  defp validate_enriched_data(killmail) do
    killmail
    |> ensure_data_consistency()
    |> run_validation()
  end

  defp run_validation(killmail) do
    case KillmailValidation.validate_killmail(killmail) do
      {:ok, _} -> handle_successful_validation(killmail)
      {:error, reasons} -> attempt_data_recovery(killmail, reasons)
    end
  end

  defp handle_successful_validation(killmail) do
    AppLogger.kill_debug("Killmail passed validation", %{
      killmail_id: killmail.killmail_id
    })

    {:ok, killmail}
  end

  defp attempt_data_recovery(killmail, reasons) do
    log_validation_failure(killmail, reasons)
    fixed_killmail = emergency_data_fix(killmail, reasons)
    revalidate_fixed_killmail(fixed_killmail, killmail.killmail_id)
  end

  defp revalidate_fixed_killmail(fixed_killmail, killmail_id) do
    case Killmail.validate_complete_data(fixed_killmail) do
      :ok -> handle_successful_fix(fixed_killmail)
      {:error, reasons} -> handle_failed_fix(killmail_id, reasons)
    end
  end

  defp handle_successful_fix(fixed_killmail) do
    AppLogger.kill_info("Emergency data fix resolved validation issues", %{
      killmail_id: fixed_killmail.killmail_id
    })

    {:ok, fixed_killmail}
  end

  defp handle_failed_fix(killmail_id, reasons) do
    AppLogger.kill_error("Killmail still failing validation after emergency fixes", %{
      killmail_id: killmail_id,
      remaining_issues: reasons
    })

    {:error, {:enrichment_validation_failed, reasons}}
  end

  # Apply emergency fixes for common validation issues
  defp emergency_data_fix(killmail, reasons) do
    AppLogger.kill_info("Attempting emergency data fix for killmail", %{
      killmail_id: killmail.killmail_id,
      issues: reasons
    })

    esi_data = Map.get(killmail, :esi_data) || %{}
    updated_esi_data = fix_system_name_if_needed(esi_data, reasons)
    Map.put(killmail, :esi_data, updated_esi_data)
  end

  defp fix_system_name_if_needed(esi_data, reasons) do
    if needs_system_name_fix?(reasons) do
      apply_system_name_fix(esi_data)
    else
      esi_data
    end
  end

  defp needs_system_name_fix?(reasons) do
    Enum.any?(reasons, &String.contains?(&1, "system name"))
  end

  defp apply_system_name_fix(esi_data) do
    system_id = Map.get(esi_data, "solar_system_id")

    if is_nil(system_id) do
      Map.put(esi_data, "solar_system_name", "Unidentified System")
    else
      fetch_or_generate_system_name(esi_data, system_id)
    end
  end

  defp fetch_or_generate_system_name(esi_data, system_id) do
    case ESIService.get_system_info(system_id) do
      {:ok, %{"name" => name}} when is_binary(name) and name != "" ->
        log_system_name_recovery(system_id, name)
        Map.put(esi_data, "solar_system_name", name)

      _ ->
        log_system_name_fallback(system_id)
        Map.put(esi_data, "solar_system_name", "System ##{system_id}")
    end
  end

  defp log_system_name_recovery(system_id, name) do
    AppLogger.kill_info("Emergency fix: Retrieved system name", %{
      system_id: system_id,
      system_name: name
    })
  end

  defp log_system_name_fallback(system_id) do
    AppLogger.kill_info("Emergency fix: Using fallback system name", %{
      system_id: system_id
    })
  end

  defp log_validation_failure(killmail, reasons) do
    debug_data = Killmail.debug_data(killmail)

    AppLogger.kill_error("Enriched killmail failed validation", %{
      killmail_id: killmail.killmail_id,
      failures: reasons,
      system_name: debug_data.system_name,
      has_victim: debug_data.has_victim_data,
      victim_name: (debug_data.has_victim_data && "present") || "missing",
      victim_ship: (debug_data.has_victim_data && "present") || "missing",
      attackers_count: debug_data.attacker_count,
      solar_system_id: debug_data.system_id
    })
  end

  # Ensure data consistency by copying enriched data throughout the struct
  defp ensure_data_consistency(killmail) do
    esi_data = killmail.esi_data || %{}
    victim = Map.get(esi_data, "victim")

    # Ensure system name is consistent throughout the structure
    esi_data =
      case Map.get(esi_data, "solar_system_name") do
        name when is_binary(name) and name != "" ->
          # Ensure system name is available if not already set
          updated_esi_data = Map.put(esi_data, "solar_system_name", name)

          # Copy to victim if present and missing
          if is_map(victim) && !Map.has_key?(victim, "solar_system_name") do
            updated_victim = Map.put(victim, "solar_system_name", name)
            Map.put(updated_esi_data, "victim", updated_victim)
          else
            updated_esi_data
          end

        _ ->
          esi_data
      end

    # Return updated killmail with consistent ESI data
    Map.put(killmail, :esi_data, esi_data)
  end
end
