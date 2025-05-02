defmodule WandererNotifier.KillmailProcessing.Pipeline do
  @moduledoc """
  Standardized pipeline for processing killmails.
  Handles both realtime and historical processing modes.
  """

  alias WandererNotifier.Api.ESI.Service, as: ESIService
  alias WandererNotifier.Core.Stats
  alias WandererNotifier.Data.Killmail
  alias WandererNotifier.KillmailProcessing.{Context, Metrics}
  alias WandererNotifier.Logger.Logger, as: AppLogger
  alias WandererNotifier.Notifications.Determiner.Kill, as: KillDeterminer
  alias WandererNotifier.Processing.Killmail.{Enrichment, Notification}

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
         {:ok, enriched} <- enrich_killmail(killmail) do
      case check_tracking(enriched) do
        {:ok, tracked} ->
          with {:ok, persisted} <- maybe_persist_killmail(tracked, ctx),
               {:ok, should_notify, reason} <- check_notification(persisted, ctx),
               {:ok, result} <- maybe_send_notification(persisted, should_notify, ctx) do
            Metrics.track_processing_complete(ctx, {:ok, result})

            log_killmail_outcome(enriched, ctx,
              persisted: true,
              notified: should_notify,
              reason: reason
            )

            {:ok, result}
          else
            error ->
              Metrics.track_processing_error(ctx)
              log_killmail_error(enriched, ctx, error)
              error
          end

        {:error, {:skipped, reason}} ->
          Metrics.track_processing_skipped(ctx)
          log_killmail_outcome(enriched, ctx, persisted: false, notified: false, reason: reason)
          {:ok, :skipped}
      end
    else
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

    with {:ok, esi_data} <- ESIService.get_killmail(kill_id, hash) do
      zkb_map = Map.get(zkb_data, "zkb", %{})
      killmail = Killmail.new(kill_id, zkb_map, esi_data)
      {:ok, killmail}
    else
      error ->
        AppLogger.kill_error("Failed to fetch ESI data for kill #{kill_id}")
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
    # Get system info directly from ESI data
    system_id =
      case killmail do
        %Killmail{esi_data: %{"solar_system_id" => id}} when is_integer(id) ->
          to_string(id)

        %{"esi_data" => %{"solar_system_id" => id}} when is_integer(id) ->
          to_string(id)

        _ ->
          "unknown"
      end

    # Check if system or character is tracked
    is_tracked_system = KillDeterminer.tracked_system?(system_id)
    has_tracked_char = KillDeterminer.has_tracked_character?(killmail)

    if is_tracked_system || has_tracked_char do
      {:ok, killmail}
    else
      {:error, {:skipped, "Not tracked by any character or system"}}
    end
  end

  @spec maybe_persist_killmail(killmail(), Context.t()) :: result()
  defp maybe_persist_killmail(killmail, ctx) do
    case WandererNotifier.Resources.KillmailPersistence.maybe_persist_killmail(
           killmail,
           ctx.character_id
         ) do
      {:ok, :persisted} ->
        {:ok, killmail}

      {:ok, :not_persisted} ->
        {:ok, killmail}

      :ignored ->
        {:ok, killmail}

      {:error, error} ->
        {:error, error}
    end
  end

  @spec check_notification(killmail(), Context.t()) :: {:ok, boolean(), String.t()}
  defp check_notification(killmail, ctx) do
    # Get system info directly from ESI data
    system_id =
      case killmail do
        %Killmail{esi_data: %{"solar_system_id" => id}} when is_integer(id) ->
          to_string(id)

        %{"esi_data" => %{"solar_system_id" => id}} when is_integer(id) ->
          to_string(id)

        _ ->
          "unknown"
      end

    # Check if system or character is tracked
    is_tracked_system = KillDeterminer.tracked_system?(system_id)
    has_tracked_char = KillDeterminer.has_tracked_character?(killmail)
    should_notify = is_tracked_system || has_tracked_char

    # Only send notifications for realtime processing
    if Context.realtime?(ctx) do
      {:ok, should_notify,
       if(should_notify, do: nil, else: "Not tracked by any character or system")}
    else
      {:ok, false, "Not realtime processing"}
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

    # Get system info from ESI data
    {system_id, system_name} =
      case killmail do
        %Killmail{esi_data: %{"solar_system_id" => id, "solar_system_name" => name}}
        when is_integer(id) ->
          {to_string(id), name}

        %Killmail{esi_data: %{"solar_system_id" => id}} when is_integer(id) ->
          {to_string(id), "unknown"}

        %{"esi_data" => %{"solar_system_id" => id, "solar_system_name" => name}}
        when is_integer(id) ->
          {to_string(id), name}

        %{"esi_data" => %{"solar_system_id" => id}} when is_integer(id) ->
          {to_string(id), "unknown"}

        _ ->
          {"unknown", "unknown"}
      end

    # Compose outcome message
    _character_name = (ctx && ctx.character_name) || "Websocket kill #{kill_id}"
    {_message, status} = get_log_details(persisted, notified, reason)

    # Log all outcomes
    AppLogger.kill_info(
      "Kill #{kill_id} (#{status}) (system: #{system_name} [#{system_id}]) (persisted: #{persisted}, notified: #{notified}, reason: #{reason})"
    )
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

  defp format_error_info(error) do
    %{error: inspect(error)}
  end

  defp get_kill_id(%Killmail{} = killmail), do: killmail.killmail_id
  defp get_kill_id(%{"killmail_id" => id}), do: id
  defp get_kill_id(%{killmail_id: id}), do: id

  defp get_kill_id(data) do
    AppLogger.kill_error("Failed to extract kill_id", %{
      data: inspect(data)
    })

    nil
  end
end
