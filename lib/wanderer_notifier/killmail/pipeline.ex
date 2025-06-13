defmodule WandererNotifier.Killmail.Pipeline do
  @moduledoc """
  Standardized pipeline for processing killmails.
  """

  require Logger

  alias WandererNotifier.Telemetry
  alias WandererNotifier.Cache.Adapter, as: Cache
  alias WandererNotifier.Killmail.{Context, Killmail, Enrichment, Notification, Schema}
  alias WandererNotifier.Logger.ErrorLogger
  alias WandererNotifier.Logger.Logger, as: AppLogger

  @type zkb_data :: map()
  @type result :: {:ok, String.t() | :skipped} | {:error, term()}

  @timeout_error WandererNotifier.ESI.Service.TimeoutError
  @api_error WandererNotifier.ESI.Service.ApiError

  @spec process_killmail(zkb_data, Context.t()) :: result
  def process_killmail(zkb_data, context) do
    {ctx, kill_id, system_id} = setup_context(zkb_data, context)
    Telemetry.processing_started(kill_id)

    run_pipeline(zkb_data, ctx, kill_id, system_id)
  rescue
    exception ->
      ErrorLogger.log_kill_error("Pipeline crash",
        kill_id: get_kill_id(zkb_data),
        error: inspect(exception)
      )

      {:error, {:unexpected_error, exception}}
  end

  # — Context & Extraction Helpers —————————————————————————————————————

  defp setup_context(data, ctx) do
    ctx = ensure_context(ctx)
    kill_id = get_kill_id(data)
    system_id = get_system_id(data)
    {Map.put(ctx, :system_id, system_id), kill_id, system_id}
  end

  defp get_kill_id(data) do
    Map.get(data, Schema.killmail_id()) ||
      Map.get(data, Schema.kill_id())
  end

  defp get_system_id(data) do
    get_in(data, ["killmail", Schema.solar_system_id()]) ||
      get_in(data, [Schema.solar_system_id()])
  end

  defp ensure_context(%Context{} = ctx), do: ctx
  defp ensure_context(_), do: Context.new()

  # — Main Pipeline ————————————————————————————————————————————————————

  defp run_pipeline(zkb_data, ctx, kill_id, system_id) do
    with {:ok, :new} <- dedupe(kill_id),
         {:ok, %{should_notify: true}} <- should_notify_tracking?(zkb_data, kill_id, system_id),
         {:ok, _km_id} <- extract_killmail_id(zkb_data),
         {:ok, %Killmail{} = killmail} <- build_and_enrich(zkb_data),
         {:ok, %{should_notify: true}} <- check_requirements(killmail, ctx) do
      send_notification(killmail, ctx)
    else
      {:ok, :duplicate} ->
        handle_notification_skipped(kill_id, system_id, :duplicate)

      {:ok, %{should_notify: false, reason: r}} ->
        handle_notification_skipped(kill_id, system_id, r)

      {:error, reason} ->
        handle_error(zkb_data, ctx, reason)
    end
  end

  defp dedupe(kill_id) do
    case deduplication_module().check(:kill, kill_id) do
      {:ok, :new} -> {:ok, :new}
      {:ok, :duplicate} -> {:ok, :duplicate}
      {:error, reason} -> {:error, reason}
      other -> {:error, {:invalid_dedup_response, other}}
    end
  end

  # — Tracking-based Notification Filter ——————————————————————————————————

  defp should_notify_tracking?(zkb_data, kill_id, system_id) do
    case {check_system_tracking(system_id), check_character_tracking(zkb_data)} do
      {{:ok, true}, _} ->
        {:ok, %{should_notify: true}}

      {_, {:ok, true}} ->
        {:ok, %{should_notify: true}}

      {{:ok, _}, {:ok, _}} ->
        {:ok, %{should_notify: false, reason: :no_tracked_entities}}

      {{:error, r}, _} ->
        log_flag_error("system tracking", r, kill_id, system_id)
        {:error, r}
    end
  end

  defp check_system_tracking(nil), do: {:ok, false}

  defp check_system_tracking(id) do
    case system_module().is_tracked?(id) do
      b when is_boolean(b) -> {:ok, b}
      o -> {:error, {:invalid_system_response, o}}
    end
  end

  defp check_character_tracking(data) do
    victim =
      get_in(data, ["killmail", Schema.victim()]) ||
        get_in(data, [Schema.victim()])

    with %{"character_id" => id} when not is_nil(id) <- victim,
         {:ok, tracked} <- character_module().is_tracked?(id) do
      {:ok, tracked}
    else
      _ -> {:ok, false}
    end
  end

  defp log_flag_error(stage, reason, kill_id, system_id) do
    AppLogger.kill_error("Error checking #{stage}",
      kill_id: kill_id,
      system: get_system_name(system_id),
      error: inspect(reason)
    )
  end

  # — Killmail ID Extraction ————————————————————————————————————————————

  defp extract_killmail_id(%Killmail{killmail_id: id}) do
    validate_killmail_id(id)
  end

  defp extract_killmail_id(%{} = data) do
    id = get_kill_id(data)
    validate_killmail_id(id)
  end

  defp validate_killmail_id(id) when is_integer(id) do
    {:ok, to_string(id)}
  end

  defp validate_killmail_id(id) when is_binary(id) and id != "" do
    {:ok, id}
  end

  defp validate_killmail_id(invalid_id) do
    ErrorLogger.log_kill_error("Invalid killmail ID",
      data: inspect(invalid_id),
      module: __MODULE__
    )

    {:error, :invalid_killmail_id}
  end

  # — Build & Enrich ——————————————————————————————————————————————————

  defp build_and_enrich(data) do
    with {:ok, km} <- build_killmail(data),
         {:ok, enriched} <- enrich(km) do
      {:ok, enriched}
    end
  end

  defp build_killmail(data) when is_map(data) do
    id = get_kill_id(data)
    hash = get_in(data, ["zkb", "hash"])
    cache = Application.get_env(:wanderer_notifier, :cache_name, :wanderer_cache)
    key = "killmail:#{id}"

    case Cache.get(cache, key) do
      {:ok, cached} when not is_nil(cached) ->
        {:ok, Killmail.new(id, Map.get(data, "zkb", %{}), cached)}

      _ ->
        fetch_from_esi(id, hash, data, cache, key)
    end
  end

  defp fetch_from_esi(id, hash, data, cache, key) do
    case esi_service().get_killmail(id, hash, []) do
      {:ok, %{} = esi} ->
        Cache.set(cache, key, esi, :timer.hours(24))
        {:ok, Killmail.new(id, Map.get(data, "zkb", %{}), esi)}

      {:ok, nil} ->
        {:error, :esi_data_missing}

      {:ok, _invalid} ->
        {:error, :invalid_esi_data}

      _ ->
        {:error, :create_failed}
    end
  end

  defp enrich(km) do
    Enrichment.enrich_killmail_data(km)
    |> case do
      {:ok, enriched} -> restore_system_id(enriched, km)
      other -> other
    end
  rescue
    _ in @timeout_error -> {:error, :timeout}
    _ in @api_error -> {:error, :api_error}
  end

  defp restore_system_id(enriched, original) do
    if is_nil(enriched.system_id) do
      id = get_in(original.esi_data, ["solar_system_id"])
      {:ok, %{enriched | system_id: id}}
    else
      {:ok, enriched}
    end
  end

  # — Notification-enabled Filter ——————————————————————————————————————

  defp check_requirements(%Killmail{} = km, _ctx) do
    cfg = config_module().get_config()

    # 1) Global notifications on?
    if Map.get(cfg, :notifications_enabled, false) do
      # 2) System vs Kill-level
      key = notification_key(km)
      reason = notification_reason(km)

      if Map.get(cfg, key, false) do
        {:ok, %{should_notify: true}}
      else
        {:ok, %{should_notify: false, reason: reason}}
      end
    else
      {:ok, %{should_notify: false, reason: :notifications_disabled}}
    end
  end

  defp notification_key(%{system_id: id}) when not is_nil(id),
    do: :system_notifications_enabled

  defp notification_key(_),
    do: :kill_notifications_enabled

  defp notification_reason(%{system_id: id}) when not is_nil(id),
    do: :system_notifications_disabled

  defp notification_reason(_),
    do: :kill_notifications_disabled

  # — Notification Sending & Skipping —————————————————————————————————————

  @spec send_notification(Killmail.t(), Context.t()) :: result
  defp send_notification(%Killmail{} = km, _ctx) do
    case Notification.send_kill_notification(km, km.killmail_id) do
      {:ok, _} ->
        Telemetry.killmail_notified(km.killmail_id, get_system_name_from_killmail(km))
        AppLogger.kill_info("💀 ✅ Killmail #{km.killmail_id} notified")
        {:ok, km.killmail_id}

      {:error, reason} ->
        handle_error(km, nil, reason)
    end
  end

  defp handle_notification_skipped(kill_id, system_id, reason) do
    Telemetry.processing_skipped(kill_id, reason)

    AppLogger.kill_info(
      "💀 #{get_reason_emoji(reason)} ##{kill_id} | #{get_system_name(system_id)} | #{get_reason_text(reason)}"
    )

    {:ok, :skipped}
  end

  # — Error Handling ——————————————————————————————————————————————————

  defp handle_error(data, ctx, reason) do
    kill_id = safe_extract_killmail_id(data)

    Telemetry.processing_error(kill_id, reason)
    log_error(kill_id, ctx, reason)
    {:error, reason}
  end

  defp log_error(kill_id, ctx, reason) do
    ErrorLogger.log_kill_error("Pipeline error",
      kill_id: kill_id,
      context: ctx,
      error: inspect(reason)
    )
  end

  defp safe_extract_killmail_id(data) do
    case extract_killmail_id(data) do
      {:ok, id} -> id
      _ -> "unknown"
    end
  end

  # — Utilities —————————————————————————————————————————————————————————

  defp get_reason_emoji(:duplicate), do: "♻️"
  defp get_reason_emoji(:no_tracked_entities), do: "🚫"
  defp get_reason_emoji(:notifications_disabled), do: "⏸️"
  defp get_reason_emoji(:system_notifications_disabled), do: "🗺️❌"
  defp get_reason_emoji(:kill_notifications_disabled), do: "💀❌"

  defp get_reason_text(reason),
    do: reason |> Atom.to_string() |> String.replace("_", " ") |> String.capitalize()

  defp get_system_name(nil), do: "unknown"
  defp get_system_name(system_id), do: WandererNotifier.Killmail.Cache.get_system_name(system_id)

  defp get_system_name_from_killmail(%Killmail{system_name: name})
       when is_binary(name) and name != "" do
    name
  end

  defp get_system_name_from_killmail(%Killmail{system_id: sid}),
    do: WandererNotifier.Killmail.Cache.get_system_name(sid)

  # — Dependencies ——————————————————————————————————————————————————————

  defp esi_service, do: WandererNotifier.Core.Dependencies.esi_service()
  defp system_module, do: WandererNotifier.Core.Dependencies.system_module()
  defp character_module, do: WandererNotifier.Core.Dependencies.character_module()
  defp config_module, do: WandererNotifier.Core.Dependencies.config_module()
  defp deduplication_module, do: WandererNotifier.Core.Dependencies.deduplication_module()
end
