defmodule WandererNotifier.KillmailProcessing.Pipeline do
  @moduledoc """
  Standardized pipeline for processing killmails.
  Handles both realtime and historical processing modes.
  """

  require Logger

  alias WandererNotifier.Api.ESI.Service, as: ESIService
  alias WandererNotifier.Core.Stats
  alias WandererNotifier.Data.Killmail
  alias WandererNotifier.KillmailProcessing.{Context, Metrics}
  alias WandererNotifier.Logger.Logger, as: AppLogger
  alias WandererNotifier.Notifications.Determiner.Kill, as: KillDeterminer
  alias WandererNotifier.Processing.Killmail.{Enrichment, Notification}
  alias WandererNotifier.Resources.KillmailPersistence

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
         {:ok, persisted} <- maybe_persist_killmail(tracked, ctx),
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
      log_killmail_error(killmail, nil, error)
      {:error, :enrichment_failed}
  end

  @spec check_tracking(killmail()) :: result()
  defp check_tracking(killmail) do
    case KillDeterminer.should_notify?(killmail) do
      {:ok, %{should_notify: true}} -> {:ok, killmail}
      {:ok, %{should_notify: false, reason: reason}} -> {:error, {:skipped, reason}}
    end
  end

  @spec maybe_persist_killmail(killmail(), Context.t()) :: result()
  defp maybe_persist_killmail(killmail, ctx) do
    case KillmailPersistence.maybe_persist_killmail(killmail, ctx.character_id) do
      {:ok, :persisted} ->
        Metrics.track_persistence(ctx)
        {:ok, killmail}

      {:ok, :already_exists} ->
        {:ok, killmail}

      :ignored ->
        {:ok, killmail}

      error ->
        error
    end
  end

  @spec check_notification(killmail(), Context.t()) :: {:ok, boolean()}
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

    case {persisted, notified, reason} do
      {true, true, _} ->
        AppLogger.kill_info("[KILLMAIL] Saved and notified", %{
          kill_id: kill_id,
          kill_time: kill_time,
          character_id: ctx.character_id,
          character_name: ctx.character_name,
          batch_id: ctx.batch_id,
          status: "saved_and_notified",
          reason: reason
        })

      {true, false, "Duplicate kill"} ->
        AppLogger.kill_debug("[KILLMAIL] Duplicate kill", %{
          kill_id: kill_id,
          kill_time: kill_time,
          character_id: ctx.character_id,
          character_name: ctx.character_name,
          batch_id: ctx.batch_id,
          status: "duplicate",
          reason: "already_exists"
        })

      {true, false, _} ->
        AppLogger.kill_info("[KILLMAIL] Saved without notification", %{
          kill_id: kill_id,
          kill_time: kill_time,
          character_id: ctx.character_id,
          character_name: ctx.character_name,
          batch_id: ctx.batch_id,
          status: "saved",
          reason: reason
        })

      {false, false, _} ->
        AppLogger.kill_debug("[KILLMAIL] Skipped", %{
          kill_id: kill_id,
          kill_time: kill_time,
          character_id: ctx.character_id,
          character_name: ctx.character_name,
          batch_id: ctx.batch_id,
          status: "skipped",
          reason: reason
        })
    end
  end

  defp log_killmail_error(killmail, ctx, error) do
    kill_id = get_kill_id(killmail)
    kill_time = Map.get(killmail, "killmail_time")

    # Handle nil context gracefully
    character_id = if ctx, do: ctx.character_id, else: nil
    character_name = if ctx, do: ctx.character_name, else: "unknown"
    batch_id = if ctx, do: ctx.batch_id, else: "unknown"

    AppLogger.kill_error("[KILLMAIL] Processing failed", %{
      kill_id: kill_id,
      kill_time: kill_time,
      character_id: character_id,
      character_name: character_name,
      batch_id: batch_id,
      status: "error",
      error: inspect(error)
    })
  end

  defp get_kill_id(%Killmail{} = killmail), do: killmail.killmail_id
  defp get_kill_id(%{"killmail_id" => id}), do: id
  defp get_kill_id(%{killmail_id: id}), do: id

  defp get_kill_id(data) do
    AppLogger.kill_error("[KILLMAIL] Failed to extract kill_id", %{
      data: inspect(data)
    })

    nil
  end
end
