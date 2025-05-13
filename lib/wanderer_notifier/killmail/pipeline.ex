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
         {:ok, enriched} <- enrich(killmail) do
      # Check if notification is needed using configurable determiner
      notification_result = notification_determiner().should_notify?(enriched)

      case notification_result do
        {:ok, %{should_notify: true, reason: _reason}} ->
          case dispatch_notification(enriched, true, ctx) do
            {:ok, final_killmail} ->
              maybe_track(:complete, {:ok, final_killmail})
              log_outcome(final_killmail, ctx, persisted: true, notified: true, reason: nil)
              {:ok, final_killmail}

            error ->
              maybe_track(:error)
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
  defp dispatch_notification(killmail, true, _ctx) do
    Notification.send_kill_notification(killmail, killmail.killmail_id)
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

  # — handle_skip/3 — logs and tracks a skipped event
  defp handle_skip(zkb_data, _ctx, reason) do
    AppLogger.kill_info("Pipeline skipping killmail", %{
      kill_id: Map.get(zkb_data, "killmail_id", "unknown"),
      reason: reason
    })

    maybe_track(:skipped)
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

  defp log_outcome(killmail, _ctx, opts) do
    AppLogger.kill_info("Pipeline processed killmail", %{
      kill_id: killmail.killmail_id,
      persisted: Keyword.get(opts, :persisted, false),
      notified: Keyword.get(opts, :notified, false),
      reason: Keyword.get(opts, :reason)
    })

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
  defp maybe_track(:skipped), do: Stats.track_processing_skipped()
  defp maybe_track(:notify), do: Stats.track_notification_sent()
  defp maybe_track(:complete, result), do: Stats.track_processing_complete(result)
end
