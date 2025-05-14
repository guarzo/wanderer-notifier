defmodule WandererNotifier.Killmail.Pipeline do
  @moduledoc """
  Standardized pipeline for processing killmails.
  """

  alias WandererNotifier.ESI.Service, as: ESIService
  alias WandererNotifier.Core.Stats
  alias WandererNotifier.Killmail.{Context, Killmail, Enrichment, Notification}
  alias WandererNotifier.Logger.Logger, as: AppLogger

  @type zkb_data :: map()
  @type result :: {:ok, Killmail.t() | :skipped} | {:error, term()}

  @doc """
  Main entry point: runs the killmail through creation, enrichment,
  tracking, notification decision, and (optional) dispatch.
  """
  @spec process_killmail(zkb_data, Context.t() | map()) :: result
  def process_killmail(zkb_data, ctx) do
    ctx = ensure_context(ctx)
    maybe_track(:start)
    Stats.increment(:kill_processed)

    with {:ok, killmail} <- build_killmail(zkb_data),
         {:ok, enriched} <- enrich(killmail),
         {:ok, final_killmail} <- dispatch_notification(enriched, true, ctx) do
      maybe_track(:complete, {:ok, final_killmail})
      log_outcome(final_killmail, ctx, persisted: true, notified: true, reason: nil)
      {:ok, final_killmail}
    else
      {:error, reason} ->
        maybe_track(:error)
        log_error(zkb_data, ctx, reason)
        {:error, reason}
    end
  end

  # Helper to ensure a proper Context struct
  defp ensure_context(%Context{} = ctx), do: ctx
  defp ensure_context(_), do: Context.new()

  # — build_killmail/1 — fetches ESI and wraps in your Killmail struct
  @spec build_killmail(zkb_data) :: {:ok, Killmail.t()} | {:error, term()}
  defp build_killmail(%{"killmail_id" => id} = zkb_data) do
    hash = get_in(zkb_data, ["zkb", "hash"])

    case ESIService.get_killmail(id, hash) do
      {:ok, esi_data} ->
        zkb_data = Map.get(zkb_data, "zkb", %{})
        killmail = Killmail.new(id, zkb_data, esi_data)
        {:ok, killmail}

      error ->
        log_error(zkb_data, nil, error)
        {:error, :create_failed}
    end
  end

  defp build_killmail(_), do: {:error, :invalid_payload}

  # — enrich/1 — delegates to your enrichment logic
  @spec enrich(Killmail.t()) :: {:ok, Killmail.t()} | {:error, term()}
  defp enrich(killmail) do
    esi_system_id = get_in(killmail, [:esi_data, "solar_system_id"])

    case Enrichment.enrich_killmail_data(killmail) do
      {:ok, enriched} ->
        system_id_after = Map.get(enriched, :system_id)
        esi_system_id_after = get_in(enriched, [:esi_data, "solar_system_id"])

        # Restore system_id if it was lost during enrichment
        enriched =
          if is_nil(system_id_after) && (esi_system_id_after || esi_system_id) do
            Map.put(enriched, :system_id, esi_system_id_after || esi_system_id)
          else
            enriched
          end

        {:ok, enriched}

      error ->
        error
    end
  rescue
    error ->
      AppLogger.error("Error during enrichment: #{inspect(error)}")
      {:error, :enrichment_failed}
  end

  # — dispatch_notification/3 — actually sends or skips the notify step
  @spec dispatch_notification(Killmail.t(), boolean(), Context.t() | map()) ::
          {:ok, Killmail.t()} | {:error, term()}
  defp dispatch_notification(killmail, true, _ctx) do
    killmail
    |> Notification.send_kill_notification(killmail.killmail_id)
    |> case do
      {:ok, _} ->
        maybe_track(:notify)
        {:ok, killmail}

      error ->
        error
    end
  end

  defp dispatch_notification({:error, _reason} = error, _, _), do: error
  defp dispatch_notification(killmail, _, _), do: {:ok, killmail}

  # — Logging & metrics helpers ———————————————————————————————————————————

  defp log_outcome(_killmail, _ctx, _opts) do
    :ok
  end

  defp log_error(data, _ctx, reason) do
    kill_id = if is_map(data), do: Map.get(data, "killmail_id", "unknown"), else: "unknown"

    AppLogger.kill_error("Pipeline error processing killmail", %{
      kill_id: kill_id,
      error: inspect(reason)
    })

    :ok
  end

  # Helper functions to track metrics using Stats instead of Metrics
  defp maybe_track(:start), do: Stats.track_processing_start()
  defp maybe_track(:error), do: Stats.track_processing_error()
  defp maybe_track(:notify), do: Stats.track_notification_sent()
  defp maybe_track(:complete, result), do: Stats.track_processing_complete(result)
end
