defmodule WandererNotifier.Killmail.Pipeline do
  @moduledoc """
  Standardized pipeline for processing killmails.
  """

  alias WandererNotifier.ESI.Service, as: ESIService
  alias WandererNotifier.Core.Stats

  alias WandererNotifier.Killmail.{
    Context,
    Killmail,
    Enrichment,
    Notification,
    NotificationChecker
  }

  alias WandererNotifier.Logger.Logger, as: AppLogger

  @type zkb_data :: map()
  @type result :: {:ok, String.t() | :skipped} | {:error, term()}

  @doc """
  Main entry point: runs the killmail through creation, enrichment,
  tracking, notification decision, and (optional) dispatch.
  """
  @spec process_killmail(zkb_data, Context.t() | map()) :: result
  def process_killmail(zkb_data, ctx) do
    ctx = ensure_context(ctx)
    Stats.increment(:kill_processed)

    with {:ok, killmail} <- build_killmail(zkb_data),
         {:ok, enriched} <- enrich(killmail),
         {:ok, %{should_notify: true}} <- NotificationChecker.should_notify?(enriched),
         {:ok, _} <- Notification.send_kill_notification(enriched, enriched.killmail_id) do
      Stats.track_notification_sent()
      log_outcome(enriched, ctx, persisted: true, notified: true, reason: nil)
      {:ok, enriched.killmail_id}
    else
      {:ok, %{should_notify: false, reason: reason}} ->
        Stats.track_processing_complete({:ok, :skipped})
        log_outcome(nil, ctx, persisted: true, notified: false, reason: reason)
        {:ok, :skipped}

      {:error, reason} ->
        Stats.track_processing_error()
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
    # Handle timeouts in ESI service calls
    e in ESIService.TimeoutError ->
      AppLogger.api_error("ESI timeout during enrichment",
        error: inspect(e),
        module: __MODULE__,
        kill_id: killmail.killmail_id,
        service: "ESI"
      )

      {:error, :timeout}

    # Handle other ESI API errors
    e in ESIService.ApiError ->
      AppLogger.api_error("ESI API error during enrichment",
        error: inspect(e),
        reason: e.reason,
        module: __MODULE__,
        kill_id: killmail.killmail_id,
        service: "ESI"
      )

      {:error, e.reason}
  end

  # — Logging & metrics helpers ———————————————————————————————————————————

  defp log_outcome(killmail, ctx, opts) do
    kill_id = if killmail, do: killmail.killmail_id, else: "unknown"
    context_id = if ctx, do: ctx.killmail_id, else: nil

    if opts[:notified] do
      AppLogger.kill_info("Killmail processed and notified",
        kill_id: kill_id,
        context_id: context_id,
        module: __MODULE__,
        source: get_in(ctx, [:options, :source])
      )
    else
      AppLogger.kill_info("Killmail processed but not notified",
        kill_id: kill_id,
        context_id: context_id,
        module: __MODULE__,
        reason: opts[:reason],
        source: get_in(ctx, [:options, :source])
      )
    end

    :ok
  end

  defp log_error(data, ctx, reason) do
    kill_id = if is_map(data), do: Map.get(data, "killmail_id", "unknown"), else: "unknown"
    context_id = if ctx, do: ctx.killmail_id, else: nil

    AppLogger.kill_error("Pipeline error processing killmail",
      kill_id: kill_id,
      context_id: context_id,
      module: __MODULE__,
      error: inspect(reason),
      source: get_in(ctx, [:options, :source])
    )

    :ok
  end
end
