defmodule WandererNotifier.Killmail.Pipeline do
  @moduledoc """
  Standardized pipeline for processing killmails.
  Handles both realtime and historical processing modes.
  """

  alias WandererNotifier.ESI.Service, as: ESIService
  alias WandererNotifier.Core.Stats
  alias WandererNotifier.Killmail.{Context, Killmail, Metrics, Enrichment, Notification}
  alias WandererNotifier.Logger.Logger, as: AppLogger

  @type killmail :: Killmail.t()
  @type result :: {:ok, killmail()} | {:error, term()}

  @doc """
  Process a killmail through the pipeline.
  """
  @spec process_killmail(map(), Context.t() | map()) :: result()
  def process_killmail(zkb_data, ctx) do
    # Only track metrics if ctx is a proper Context struct
    try_track_processing_start(ctx)
    Stats.increment(:kill_processed)

    with {:ok, killmail} <- create_killmail(zkb_data),
         {:ok, enriched} <- enrich_killmail(killmail),
         {:ok, tracked} <- check_tracking(enriched),
         {:ok, should_notify, reason} <- check_notification(tracked, ctx),
         {:ok, result} <- maybe_send_notification(tracked, should_notify, ctx) do
      try_track_processing_complete(ctx, {:ok, result})
      log_killmail_outcome(result, ctx, persisted: true, notified: should_notify, reason: reason)
      {:ok, result}
    else
      {:error, {:skipped, reason}} ->
        try_track_processing_skipped(ctx)
        # Log system name and ID for skipped killmails
        system_id = Map.get(zkb_data, "solar_system_id")
        killmail_id = Map.get(zkb_data, "killmail_id")

        AppLogger.kill_info("Skipping kill in process_killmail", %{
          kill_id: killmail_id,
          system_id: system_id,
          reason: reason
        })

        _system_name =
          case ESIService.get_system(system_id) do
            {:ok, %{"name" => name}} -> name
            _ -> "Unknown"
          end

        log_killmail_outcome(zkb_data, ctx, persisted: false, notified: false, reason: reason)

        AppLogger.kill_info("Pipeline returning :skipped for kill", %{
          killmail_id: Map.get(zkb_data, "killmail_id", "unknown"),
          reason: reason
        })

        {:ok, :skipped}

      error ->
        try_track_processing_error(ctx)
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
      {:error, reason} = error ->
        log_killmail_error(zkb_data, nil, {:error, reason})
        error

      error ->
        log_killmail_error(zkb_data, nil, error)
        {:error, :create_killmail_failed}
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
    # Handle case where killmail might be in a tuple
    actual_killmail =
      case killmail do
        {:ok, km} when is_struct(km, Killmail) -> km
        km when is_struct(km, Killmail) -> km
        _ -> killmail
      end

    # Skip duplicate tracking checks since should_notify? was already called in processor.ex
    # This corrects the double check issue and prevents valid killmails from being skipped
    kill_id = get_kill_id(actual_killmail)

    AppLogger.kill_info("Pipeline skipping duplicate tracking check for kill", %{
      kill_id: kill_id
    })

    # Simply pass through the killmail that already passed the should_notify check
    {:ok, actual_killmail}
  end

  @spec check_notification(killmail(), Context.t()) :: {:ok, boolean(), String.t()}
  defp check_notification(killmail, _ctx) do
    # Handle case where killmail might be in a tuple
    actual_killmail =
      case killmail do
        {:ok, km} when is_struct(km, Killmail) -> km
        km when is_struct(km, Killmail) -> km
        _ -> killmail
      end

    # Safe extraction for logging
    kill_id = get_kill_id(actual_killmail)

    # Skip redundant notification check - killmail has already passed notification check in processor.ex
    AppLogger.kill_info("Pipeline skipping duplicate notification check for kill", %{
      kill_id: kill_id
    })

    # Always indicate should notify as true since it already passed initial determination
    {:ok, true, nil}
  end

  @spec maybe_send_notification(killmail(), boolean(), Context.t()) :: result()
  defp maybe_send_notification(killmail, true, ctx) do
    case Notification.send_kill_notification(killmail, killmail.killmail_id) do
      {:ok, _} ->
        # Only track metrics if ctx is a proper Context struct
        cond do
          is_struct(ctx, Context) ->
            Metrics.track_notification_sent(ctx)

          is_map(ctx) and Map.has_key?(ctx, :__struct__) ->
            AppLogger.kill_warn("Skipping metrics tracking - context is not a Context struct", %{
              context_type: inspect(ctx.__struct__)
            })

          true ->
            # Handle case where ctx is not a map or doesn't have __struct__
            AppLogger.kill_warn("Skipping metrics tracking - invalid context type", %{
              context_type: inspect(ctx)
            })
        end

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
    # Handle error tuples that might be passed as killmail
    kill_id = get_kill_id_safely(killmail)
    kill_time = get_kill_time_safely(killmail)

    # Safely extract context values with nil-safe access
    character_id = if is_map(ctx), do: Map.get(ctx, :character_id)
    character_name = if is_map(ctx), do: Map.get(ctx, :character_name, "unknown")
    batch_id = if is_map(ctx), do: Map.get(ctx, :batch_id, "unknown")

    processing_mode =
      if is_map(ctx) and is_map(Map.get(ctx, :mode)), do: Map.get(ctx.mode, :mode, :default)

    metadata = %{
      kill_id: kill_id,
      kill_time: kill_time,
      character_id: character_id,
      character_name: character_name || "unknown",
      batch_id: batch_id || "unknown",
      reason: reason,
      processing_mode: processing_mode
    }

    # Determine status and message based on outcomes
    {message, status} = get_log_details(persisted, notified, reason)

    # Add status to metadata and log with appropriate level
    updated_metadata = Map.put(metadata, :status, status)

    # Use debug level for skipped and duplicates, info for others
    if status in ["skipped", "duplicate"] do
      AppLogger.kill_info(message, updated_metadata)
    else
      AppLogger.kill_info(message, updated_metadata)
    end
  end

  # Safe extraction of kill_id that handles error tuples
  defp get_kill_id_safely(killmail) do
    case killmail do
      {:error, _} -> "unknown"
      {:ok, km} when is_map(km) -> get_kill_id(km)
      km -> get_kill_id(km)
    end
  end

  # Safe extraction of kill_time that handles error tuples
  defp get_kill_time_safely(killmail) do
    case killmail do
      {:error, _} -> nil
      {:ok, km} when is_map(km) -> Map.get(km, "killmail_time")
      km when is_map(km) -> Map.get(km, "killmail_time")
      _ -> nil
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

    # Safely extract context values with nil-safe access
    character_id = if is_map(ctx), do: Map.get(ctx, :character_id)
    character_name = if is_map(ctx), do: Map.get(ctx, :character_name, "unknown")
    batch_id = if is_map(ctx), do: Map.get(ctx, :batch_id, "unknown")

    processing_mode =
      if is_map(ctx) and is_map(Map.get(ctx, :mode)), do: Map.get(ctx.mode, :mode, :default)

    # Create base metadata
    metadata = %{
      kill_id: kill_id,
      kill_time: kill_time,
      character_id: character_id,
      character_name: character_name || "unknown",
      batch_id: batch_id || "unknown",
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

  # Helper functions to safely track metrics
  defp try_track_processing_start(ctx) do
    if is_struct(ctx, Context) and function_exported?(Metrics, :track_processing_start, 1) do
      Metrics.track_processing_start(ctx)
    end
  rescue
    _ -> :ok
  end

  defp try_track_processing_complete(ctx, result) do
    if is_struct(ctx, Context) and function_exported?(Metrics, :track_processing_complete, 2) do
      Metrics.track_processing_complete(ctx, result)
    end
  rescue
    _ -> :ok
  end

  defp try_track_processing_skipped(ctx) do
    if is_struct(ctx, Context) and function_exported?(Metrics, :track_processing_skipped, 1) do
      Metrics.track_processing_skipped(ctx)
    end
  rescue
    _ -> :ok
  end

  defp try_track_processing_error(ctx) do
    if is_struct(ctx, Context) and function_exported?(Metrics, :track_processing_error, 1) do
      Metrics.track_processing_error(ctx)
    end
  rescue
    _ -> :ok
  end
end
