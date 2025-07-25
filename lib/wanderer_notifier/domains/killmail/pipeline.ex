defmodule WandererNotifier.Domains.Killmail.Pipeline do
  @moduledoc """
  Standardized pipeline for processing killmails.
  """

  require Logger

  alias WandererNotifier.Application.Telemetry
  alias WandererNotifier.Domains.Killmail.{Context, Killmail, Notification, Schema}
  alias WandererNotifier.Shared.Logger.ErrorLogger
  alias WandererNotifier.Shared.Logger.Logger, as: AppLogger

  @type zkb_data :: map()
  @type result :: {:ok, String.t() | :skipped} | {:error, term()}

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
    # Try string key first (WebSocket format), then atom key for backward compatibility
    Map.get(data, "killmail_id") || Map.get(data, :killmail_id) ||
      Map.get(data, Schema.killmail_id())
  end

  defp get_system_id(data) do
    # Try string key first (WebSocket format), then atom key for backward compatibility
    Map.get(data, "system_id") ||
      Map.get(data, :system_id) ||
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

  defp dedupe(nil), do: {:error, {:missing_kill_id, "Killmail ID cannot be nil"}}

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
    system_module().is_tracked?(id)
  end

  defp check_character_tracking(data) do
    victim = extract_victim(data)
    attackers = extract_attackers(data)

    victim_tracked = victim_tracked?(victim)
    attacker_tracked = any_attacker_tracked?(attackers)

    {:ok, victim_tracked or attacker_tracked}
  end

  defp extract_victim(data) do
    Map.get(data, "victim") ||
      Map.get(data, :victim) ||
      get_in(data, ["killmail", Schema.victim()]) ||
      get_in(data, [Schema.victim()])
  end

  defp extract_attackers(data) do
    Map.get(data, "attackers") ||
      Map.get(data, :attackers) ||
      get_in(data, ["killmail", "attackers"]) ||
      get_in(data, ["attackers"]) || []
  end

  defp victim_tracked?(%{"character_id" => id}) when is_integer(id) do
    character_tracked?(id)
  end

  defp victim_tracked?(%{character_id: id}) when is_integer(id) do
    character_tracked?(id)
  end

  defp victim_tracked?(_), do: false

  defp any_attacker_tracked?(attackers) when is_list(attackers) do
    Enum.any?(attackers, &attacker_tracked?/1)
  end

  defp any_attacker_tracked?(_), do: false

  defp attacker_tracked?(attacker) do
    character_id = Map.get(attacker, "character_id") || Map.get(attacker, :character_id)
    character_tracked?(character_id)
  end

  defp character_tracked?(nil), do: false

  defp character_tracked?(character_id) do
    case character_module().is_tracked?(character_id) do
      {:ok, true} -> true
      _ -> false
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
    # All data should now be pre-enriched from WebSocket
    build_websocket_killmail(data)
  end

  # — WebSocket Killmail Building ——————————————————————————————————————

  defp build_websocket_killmail(data) do
    killmail_id = Map.get(data, "killmail_id") || Map.get(data, :killmail_id)
    # Handle both WebSocket format ("system_id") and ZKillboard format ("solar_system_id")
    system_id =
      Map.get(data, "system_id") || Map.get(data, :system_id) ||
        Map.get(data, "solar_system_id") || Map.get(data, :solar_system_id)

    # Validate required fields
    cond do
      is_nil(killmail_id) -> {:error, :missing_killmail_id}
      is_nil(system_id) -> {:error, :missing_system_id}
      true -> build_validated_websocket_killmail(killmail_id, system_id, data)
    end
  end

  defp build_validated_websocket_killmail(killmail_id, system_id, data) do
    # Build killmail struct from pre-enriched WebSocket data
    killmail = %Killmail{
      killmail_id: to_string(killmail_id),
      system_id: system_id,
      system_name: get_system_name(system_id),
      victim: transform_websocket_victim(Map.get(data, "victim") || Map.get(data, :victim)),
      attackers:
        transform_websocket_attackers(Map.get(data, "attackers") || Map.get(data, :attackers, [])),
      zkb: Map.get(data, "zkb") || Map.get(data, :zkb, %{}),
      esi_data: %{
        "killmail_id" => killmail_id,
        "solar_system_id" => system_id,
        "killmail_time" => Map.get(data, "kill_time") || Map.get(data, :kill_time)
      },
      # Mark as enriched since it came from WebSocket
      enriched?: true
    }

    {:ok, killmail}
  end

  defp transform_websocket_victim(nil), do: %{}

  defp transform_websocket_victim(victim) when is_map(victim) do
    fields = [
      "character_id",
      "character_name",
      "corporation_id",
      "corporation_name",
      "alliance_id",
      "alliance_name",
      "ship_type_id",
      "ship_name",
      "damage_taken"
    ]

    Map.new(fields, fn field ->
      atom_field = String.to_atom(field)
      {field, Map.get(victim, atom_field) || Map.get(victim, field)}
    end)
  end

  defp transform_websocket_attackers(nil), do: []

  defp transform_websocket_attackers(attackers) when is_list(attackers) do
    Enum.map(attackers, &transform_attacker/1)
  end

  defp transform_websocket_attackers(_), do: []

  defp transform_attacker(attacker) do
    string_fields = [
      "character_id",
      "character_name",
      "corporation_id",
      "corporation_name",
      "alliance_id",
      "alliance_name",
      "ship_type_id",
      "ship_name",
      "damage_done",
      "security_status",
      "weapon_type_id"
    ]

    # Take existing string keys first, then atom keys, with defaults
    base = Map.take(attacker, string_fields)

    atom_values =
      string_fields
      |> Enum.filter(&(not Map.has_key?(base, &1)))
      |> Map.new(fn field ->
        {field, Map.get(attacker, String.to_atom(field))}
      end)

    Map.merge(base, atom_values)
    |> Map.put_new("final_blow", false)
  end

  # — Notification-enabled Filter ——————————————————————————————————————

  defp check_requirements(%Killmail{} = km, _ctx) do
    cfg = WandererNotifier.Shared.Config.get_config()

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

  defp notification_key(%{system_id: id}) when is_integer(id),
    do: :system_notifications_enabled

  defp notification_key(_),
    do: :kill_notifications_enabled

  defp notification_reason(%{system_id: id}) when is_integer(id),
    do: :system_notifications_disabled

  defp notification_reason(_),
    do: :kill_notifications_disabled

  # — Notification Sending & Skipping —————————————————————————————————————

  @spec send_notification(Killmail.t(), Context.t()) :: result
  defp send_notification(%Killmail{} = km, _ctx) do
    case Notification.send_kill_notification(km, km.killmail_id) do
      {:ok, _} ->
        Telemetry.processing_completed(km.killmail_id, {:ok, :notified})
        Telemetry.killmail_notified(km.killmail_id, get_system_name_from_killmail(km))
        AppLogger.kill_info("💀 ✅ Killmail #{km.killmail_id} notified")
        {:ok, km.killmail_id}

      {:error, reason} ->
        handle_error(km, nil, reason)
    end
  end

  defp handle_notification_skipped(kill_id, system_id, reason) do
    Telemetry.processing_completed(kill_id, {:ok, :skipped})
    Telemetry.processing_skipped(kill_id, reason)

    AppLogger.kill_info(
      "💀 #{get_reason_emoji(reason)} ##{kill_id} | #{get_system_name(system_id)} | #{get_reason_text(reason)}"
    )

    {:ok, :skipped}
  end

  # — Error Handling ——————————————————————————————————————————————————

  defp handle_error(data, ctx, reason) do
    kill_id = safe_extract_killmail_id(data)

    Telemetry.processing_completed(kill_id, {:error, reason})
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

  @reason_emojis %{
    duplicate: "♻️",
    no_tracked_entities: "🚫",
    notifications_disabled: "⏸️",
    system_notifications_disabled: "🗺️❌",
    kill_notifications_disabled: "💀❌"
  }

  defp get_reason_emoji(reason), do: Map.get(@reason_emojis, reason, "❓")

  defp get_reason_text(reason),
    do: reason |> Atom.to_string() |> String.replace("_", " ") |> String.capitalize()

  defp get_system_name(nil), do: "unknown"

  defp get_system_name(system_id),
    do: killmail_cache_module().get_system_name(system_id)

  defp get_system_name_from_killmail(%Killmail{system_name: name})
       when is_binary(name) and name != "" do
    name
  end

  defp get_system_name_from_killmail(%Killmail{system_id: sid}),
    do: killmail_cache_module().get_system_name(sid)

  # — Dependencies ——————————————————————————————————————————————————————

  defp system_module, do: WandererNotifier.Application.Services.Dependencies.system_module()
  defp character_module, do: WandererNotifier.Application.Services.Dependencies.character_module()

  defp deduplication_module,
    do: WandererNotifier.Application.Services.Dependencies.deduplication_module()

  defp killmail_cache_module,
    do: WandererNotifier.Application.Services.Dependencies.killmail_cache_module()
end
