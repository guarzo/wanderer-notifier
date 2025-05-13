defmodule WandererNotifier.Killmail.Pipeline do
  @moduledoc """
  Standardized pipeline for processing killmails.
  Handles both realtime and historical modes.
  """

  alias WandererNotifier.ESI.Service, as: ESIService
  alias WandererNotifier.Core.Stats
  alias WandererNotifier.Killmail.{Context, Killmail, Metrics, Enrichment, Notification}
  alias WandererNotifier.Logger.Logger, as: AppLogger

  @type zkb_data :: map()
  @type result :: {:ok, Killmail.t() | :skipped} | {:error, term()}

  @doc """
  Main entry point: runs the killmail through creation, enrichment,
  tracking, notification decision, and (optional) dispatch.
  """
  @spec process_killmail(zkb_data, Context.t() | map()) :: result
  def process_killmail(zkb_data, ctx) do
    maybe_track(:start, ctx)
    Stats.increment(:kill_processed)

    with {:ok, killmail} <- build_killmail(zkb_data),
         {:ok, enriched} <- enrich(killmail) do
      # Check if notification is needed using configurable determiner
      notification_result = notification_determiner().should_notify?(enriched)

      case notification_result do
        {:ok, %{should_notify: true, reason: _reason}} ->
          case dispatch_notification(enriched, true, ctx) do
            {:ok, final_killmail} ->
              maybe_track(:complete, ctx, {:ok, final_killmail})
              log_outcome(final_killmail, ctx, persisted: true, notified: true, reason: nil)
              {:ok, final_killmail}

            error ->
              maybe_track(:error, ctx)
              log_error(zkb_data, ctx, error)
              error
          end

        {:ok, %{should_notify: false, reason: reason}} ->
          handle_skip(zkb_data, ctx, reason)

        _ ->
          # Handle unexpected notification determiner results
          handle_skip(zkb_data, ctx, "Unknown notification status")
      end
    else
      {:error, reason} ->
        maybe_track(:error, ctx)
        log_error(zkb_data, ctx, reason)
        {:error, reason}
    end
  end

  # — build_killmail/1 — fetches ESI and wraps in your Killmail struct
  @spec build_killmail(zkb_data) :: {:ok, Killmail.t()} | {:error, term()}
  defp build_killmail(%{"killmail_id" => id} = zkb_data) do
    hash = get_in(zkb_data, ["zkb", "hash"])

    case ESIService.get_killmail(id, hash) do
      {:ok, esi_data} ->
        {:ok, Killmail.new(id, Map.get(zkb_data, "zkb", %{}), esi_data)}

      error ->
        log_error(zkb_data, nil, error)
        {:error, :create_failed}
    end
  end

  defp build_killmail(_), do: {:error, :invalid_payload}

  # — enrich/1 — delegates to your enrichment logic
  @spec enrich(Killmail.t()) :: {:ok, Killmail.t()} | {:error, term()}
  defp enrich(killmail) do
    {:ok, Enrichment.enrich_killmail_data(killmail)}
  rescue
    _ -> {:error, :enrichment_failed}
  end

  # — dispatch_notification/3 — actually sends or skips the notify step
  @spec dispatch_notification(Killmail.t(), boolean(), Context.t() | map()) ::
          {:ok, Killmail.t()} | {:error, term()}
  defp dispatch_notification(killmail, true, ctx) do
    Notification.send_kill_notification(killmail, killmail.killmail_id)
    |> case do
      {:ok, _} ->
        maybe_track(:notify, ctx)
        {:ok, killmail}

      error ->
        error
    end
  end

  defp dispatch_notification({:error, _reason} = error, _, _), do: error
  defp dispatch_notification(killmail, _, _), do: {:ok, killmail}

  # — handle_skip/3 — logs and tracks a skipped event
  defp handle_skip(zkb_data, ctx, reason) do
    AppLogger.kill_info("Pipeline skipping killmail", %{
      kill_id: Map.get(zkb_data, "killmail_id", "unknown"),
      reason: reason
    })

    maybe_track(:skipped, ctx)
    {:ok, :skipped}
  end

  # Get the notification determiner module from application config
  defp notification_determiner do
    Application.get_env(
      :wanderer_notifier,
      :notification_determiner,
      WandererNotifier.Notifications.Determiner.Kill
    )
  end

  # — Logging & metrics helpers ———————————————————————————————————————————

  defp log_outcome(_killmail, _ctx, _opts), do: :ok
  defp log_error(_data, _ctx, _reason), do: :ok

  defp maybe_track(:start, ctx), do: if_ctx(ctx, &Metrics.track_processing_start/1)
  defp maybe_track(:error, ctx), do: if_ctx(ctx, &Metrics.track_processing_error/1)
  defp maybe_track(:skipped, ctx), do: if_ctx(ctx, &Metrics.track_processing_skipped/1)
  defp maybe_track(:notify, ctx), do: if_ctx(ctx, &Metrics.track_notification_sent/1)
  defp maybe_track(:complete, ctx, r), do: if_ctx(ctx, &Metrics.track_processing_complete(&1, r))

  defp if_ctx(%Context{} = c, fun), do: fun.(c)
  defp if_ctx(_, _), do: :ok
end
