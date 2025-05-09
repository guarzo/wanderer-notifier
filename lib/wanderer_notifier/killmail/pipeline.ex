defmodule WandererNotifier.Killmail.Pipeline do
  @moduledoc """
  Standardized pipeline for processing killmails.
  Handles both realtime and historical processing modes.
  """

  alias WandererNotifier.ESI.Service, as: ESIService
  alias WandererNotifier.Core.Stats
  alias WandererNotifier.Killmail.{Context, Killmail, Metrics, Enrichment, Notification}
  alias WandererNotifier.Logger.Logger, as: AppLogger
  alias WandererNotifier.Notifications.Determiner.Kill, as: KillDeterminer

  @type killmail :: Killmail.t()
  @type result :: {:ok, killmail()} | {:error, term()}

  @doc """
  Process a killmail through the pipeline.
  """
  @spec process_killmail(map(), Context.t()) :: result()
  def process_killmail(zkb_data, ctx) do
    Metrics.track_processing_start(ctx)
    Stats.increment(:kill_processed)

    with {:ok, killmail} <- create_killmail(zkb_data),
         {:ok, enriched} <- enrich_killmail(killmail),
         {:ok, tracked} <- check_tracking(enriched),
         {:ok, should_notify, reason} <- check_notification(tracked, ctx),
         {:ok, result} <- maybe_send_notification(tracked, should_notify, ctx) do
      Metrics.track_processing_complete(ctx, {:ok, result})
      log_killmail_outcome(result, ctx, persisted: true, notified: should_notify, reason: reason)
      {:ok, result}
    else
      {:error, {:skipped, reason}} ->
        Metrics.track_processing_skipped(ctx)
        # Log system name and ID for skipped killmails
        system_id = Map.get(zkb_data, "solar_system_id")
        _killmail_id = Map.get(zkb_data, "killmail_id")

        _system_name =
          case ESIService.get_system(system_id) do
            {:ok, %{"name" => name}} -> name
            _ -> "Unknown"
          end

        log_killmail_outcome(zkb_data, ctx, persisted: false, notified: false, reason: reason)
        {:ok, :skipped}

      error ->
        Metrics.track_processing_error(ctx)
        log_killmail_error(zkb_data, ctx, error)
        error
    end
  end

  @spec create_killmail(map()) :: result()
  defp create_killmail(zkb_data) do
    kill_id = Map.get(zkb_data, "killmail_id")
    hash = get_in(zkb_data, ["zkb", "hash"])

    with {:ok, esi_data} <- ESIService.get_killmail(kill_id, hash),
         zkb_map <- Map.get(zkb_data, "zkb", %{}),
         killmail <- Killmail.new(kill_id, zkb_map, esi_data) do
      {:ok, killmail}
    else
      error ->
        log_killmail_error(zkb_data, nil, error)
        error
    end
  end

  @spec enrich_killmail(killmail()) :: result()
  defp enrich_killmail(killmail) do
    enriched = Enrichment.enrich_killmail_data(killmail)
    {:ok, enriched}
  rescue
    error ->
      stacktrace = __STACKTRACE__
      log_killmail_error(killmail, nil, {error, stacktrace})
      {:error, :enrichment_failed}
  end

  @spec check_tracking(killmail()) :: result()
  defp check_tracking(killmail) do
    case KillDeterminer.should_notify?(killmail) do
      {:ok, %{should_notify: true}} -> {:ok, killmail}
      {:ok, %{should_notify: false, reason: reason}} -> {:error, {:skipped, reason}}
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

    # Use debug level for skipped and duplicates, info for others
    if status in ["skipped", "duplicate"] do
      AppLogger.kill_debug(message, updated_metadata)
    else
      AppLogger.kill_info(message, updated_metadata)
    end
  end

  # Helper function to get log message and status based on outcomes
  defp get_log_details(persisted, notified, reason) do
    case {persisted, notified, reason} do
      {true, true, _} ->
        {"Killmail saved and notified", "saved_and_notified"}

      {true, false, "Duplicate kill"} ->
        {"Duplicate killmail detected", "duplicate"}

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

  defp format_error_info({:error, reason}) do
    %{error: inspect(reason)}
  end

  defp format_error_info(error) do
    %{error: inspect(error)}
  end

  # Extract kill ID safely from various data structures
  defp get_kill_id(%{killmail_id: id}) when is_binary(id) or is_integer(id), do: id
  defp get_kill_id(%{"killmail_id" => id}) when is_binary(id) or is_integer(id), do: id
  defp get_kill_id(_), do: "unknown"
end
