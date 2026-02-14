defmodule WandererNotifier.Domains.Killmail.Pipeline do
  @moduledoc """
  Pipeline for processing killmails.

  Handles pre-enriched WebSocket data directly without unnecessary transformations.
  """

  require Logger
  alias WandererNotifier.Shared.Telemetry
  alias WandererNotifier.Domains.Killmail.Killmail
  alias WandererNotifier.Domains.Killmail.ItemProcessor
  alias WandererNotifier.Infrastructure.Cache
  alias WandererNotifier.Shared.Config
  alias WandererNotifier.Shared.Utils.Startup
  alias WandererNotifier.Shared.Utils.ErrorHandler
  alias WandererNotifier.Shared.Utils.TimeUtils
  alias WandererNotifier.Domains.Notifications.Deduplication
  alias WandererNotifier.Shared.Utils.EntityUtils

  @type killmail_data :: map()
  @type result :: {:ok, String.t() | :skipped} | {:error, term()}

  # Defensive error handling - legacy tracking clients may return errors at runtime
  @dialyzer {:nowarn_function, system_tracked_by_mode?: 1}
  @dialyzer {:nowarn_function, character_tracked_by_mode?: 1}

  defp map_registry do
    Application.get_env(
      :wanderer_notifier,
      :map_registry_module,
      WandererNotifier.Map.MapRegistry
    )
  end

  # ═══════════════════════════════════════════════════════════════════════════════
  # Public API
  # ═══════════════════════════════════════════════════════════════════════════════

  @doc """
  Main entry point for processing killmails from any source.
  """
  @spec process_killmail(killmail_data()) :: result()
  def process_killmail(killmail_data) when is_map(killmail_data) do
    # Extract kill ID early for logging and telemetry
    kill_id = extract_kill_id(killmail_data)

    if is_nil(kill_id) do
      Logger.error("Killmail missing ID", data: inspect(killmail_data), category: :killmail)
      {:error, :missing_killmail_id}
    else
      process_with_kill_id(killmail_data, kill_id)
    end
  end

  @spec process_with_kill_id(killmail_data(), String.t()) :: result()
  defp process_with_kill_id(killmail_data, kill_id) do
    Telemetry.processing_started(kill_id)

    ErrorHandler.with_error_handling(fn -> process_killmail_pipeline(killmail_data, kill_id) end)
    |> handle_pipeline_errors(kill_id)
  end

  @spec process_killmail_pipeline(killmail_data(), String.t()) :: result()
  defp process_killmail_pipeline(killmail_data, kill_id) do
    Logger.info("[Pipeline] Starting pipeline for killmail #{kill_id}")

    # Check for duplicates first (in addition to WebSocket client deduplication)
    duplicate_check = check_duplicate(kill_id)
    Logger.info("[Pipeline] Duplicate check for #{kill_id}: #{inspect(duplicate_check)}")

    with {:ok, :new} <- duplicate_check,
         {:ok, %Killmail{} = killmail} <- build_killmail(killmail_data),
         {:ok, true} <- should_notify?(killmail) do
      send_notification(killmail)
    else
      {:ok, :duplicate} ->
        handle_duplicate_killmail(kill_id)

      {:ok, false} ->
        handle_non_tracked_killmail(kill_id, killmail_data)

      {:error, reason} ->
        Logger.info("[Pipeline] Error processing #{kill_id}: #{inspect(reason)}")
        handle_error(kill_id, reason)
    end
  end

  @spec handle_pipeline_errors(result(), String.t()) :: result()
  defp handle_pipeline_errors(result, kill_id) do
    case result do
      {:error, {:exception, exception}} ->
        handle_error(kill_id, {:pipeline_crash, exception})

      {:error, {:exit, reason}} ->
        handle_error(kill_id, {:pipeline_exit, reason})

      result ->
        result
    end
  end

  @spec handle_duplicate_killmail(String.t()) :: result()
  defp handle_duplicate_killmail(kill_id) do
    Logger.info("[Pipeline] Killmail #{kill_id} is a duplicate")
    handle_skipped(kill_id, :duplicate)
  end

  @spec handle_non_tracked_killmail(String.t(), killmail_data()) :: result()
  defp handle_non_tracked_killmail(kill_id, killmail_data) do
    # Log tracking cache state to diagnose why kills are being dropped
    log_tracking_cache_state(kill_id)

    Logger.info("[Pipeline] Killmail #{kill_id} should_notify returned false")
    # Get killmail for logging details even though we're not notifying
    case build_killmail(killmail_data) do
      {:ok, %Killmail{} = killmail} ->
        handle_skipped_with_details(kill_id, :not_tracked, killmail)

      _ ->
        handle_skipped(kill_id, :not_tracked)
    end
  end

  defp log_tracking_cache_state(kill_id) do
    # Check what tracking data is available
    systems_result = Cache.get(Cache.Keys.map_systems())
    chars_result = Cache.get(Cache.Keys.map_characters())

    systems_count =
      case systems_result do
        {:ok, systems} when is_list(systems) -> length(systems)
        _ -> 0
      end

    chars_count =
      case chars_result do
        {:ok, chars} when is_list(chars) -> length(chars)
        _ -> 0
      end

    Logger.warning(
      "[Pipeline] Kill #{kill_id} NOT TRACKED - Cache state: #{systems_count} systems, #{chars_count} characters tracked. " <>
        "If both are 0, SSE connection may have failed to populate tracking data."
    )
  end

  # ═══════════════════════════════════════════════════════════════════════════════
  # Core Processing Steps
  # ═══════════════════════════════════════════════════════════════════════════════

  @spec extract_kill_id(killmail_data()) :: String.t() | nil
  defp extract_kill_id(data) do
    # Handle both string and atom keys
    kill_id = data["killmail_id"] || data[:killmail_id]

    case kill_id do
      id when is_integer(id) -> Integer.to_string(id)
      id when is_binary(id) and id != "" -> id
      _ -> nil
    end
  end

  @spec build_killmail(killmail_data()) :: {:ok, Killmail.t()} | {:error, term()}
  defp build_killmail(data) do
    # Data from WebSocket is pre-enriched, so we can build directly
    kill_id = extract_kill_id(data)
    system_id = extract_system_id(data)

    Logger.debug(
      "[Pipeline] Building killmail - ID: #{inspect(kill_id)}, System: #{inspect(system_id)}"
    )

    Logger.debug("[Pipeline] Raw data keys: #{inspect(Map.keys(data))}")

    cond do
      is_nil(kill_id) ->
        {:error, :missing_killmail_id}

      is_nil(system_id) ->
        {:error, :missing_system_id}

      not is_integer(system_id) ->
        {:error, {:invalid_system_id, system_id}}

      true ->
        killmail = Killmail.from_websocket_data(kill_id, system_id, data)

        attacker_count = length(killmail.attackers || [])

        Logger.debug(
          "[Pipeline] Built killmail - Victim ID: #{inspect(killmail.victim_character_id)}, Attackers: #{attacker_count}"
        )

        {:ok, killmail}
    end
  end

  @spec extract_system_id(killmail_data()) :: integer() | nil
  defp extract_system_id(data) do
    # Try EntityUtils first, then fallback to nested killmail structure
    EntityUtils.extract_system_id(data) ||
      data
      |> get_in(["killmail", "solar_system_id"])
      |> EntityUtils.normalize_id()
  end

  @spec check_duplicate(String.t()) :: {:ok, :new | :duplicate} | {:error, term()}
  defp check_duplicate(kill_id) do
    case Deduplication.check(:kill, kill_id) do
      {:ok, :new} ->
        {:ok, :new}

      {:ok, :duplicate} ->
        {:ok, :duplicate}

      {:error, reason} ->
        # Log the error but don't fail the pipeline - treat as new to be safe
        Logger.warning(
          "Deduplication check failed, treating as new - killmail_id: #{kill_id}, error: #{inspect(reason)}"
        )

        {:ok, :new}
    end
  end

  @spec should_notify?(Killmail.t()) :: {:ok, boolean()} | {:error, term()}
  defp should_notify?(%Killmail{} = killmail) do
    # Check global notification settings first
    enabled = notifications_enabled?()
    Logger.debug("[Pipeline] Notifications enabled: #{enabled}")

    if enabled do
      check_entity_tracking(killmail)
    else
      {:ok, false}
    end
  end

  @spec check_entity_tracking(Killmail.t()) :: {:ok, boolean()} | {:error, term()}
  defp check_entity_tracking(%Killmail{} = killmail) do
    # Check if this killmail involves tracked entities
    Logger.info(
      "[Pipeline] Checking tracking for killmail #{killmail.killmail_id}, system_id: #{killmail.system_id}"
    )

    with {:ok, system_tracked} <- system_tracked?(killmail.system_id),
         {:ok, character_tracked} <- character_tracked?(killmail) do
      is_tracked = system_tracked or character_tracked
      log_tracking_status(killmail.killmail_id, system_tracked, character_tracked, is_tracked)

      {:ok, is_tracked}
    end
  end

  defp log_tracking_status(killmail_id, system_tracked, character_tracked, is_tracked) do
    Logger.info(
      "[Pipeline] Tracking status for killmail #{killmail_id}: system_tracked=#{system_tracked}, character_tracked=#{character_tracked}, is_tracked=#{is_tracked}"
    )

    if is_tracked do
      tracking_reason = get_tracking_reason(system_tracked, character_tracked)
      Logger.info("[Pipeline] Killmail #{killmail_id} IS TRACKED: #{tracking_reason}")
    else
      Logger.debug("[Pipeline] Killmail #{killmail_id} not tracked")
    end
  end

  defp get_tracking_reason(true, true), do: "system+character"
  defp get_tracking_reason(true, false), do: "system"
  defp get_tracking_reason(false, true), do: "character"
  defp get_tracking_reason(false, false), do: "none"

  @spec notifications_enabled?() :: boolean()
  defp notifications_enabled? do
    enabled = WandererNotifier.Shared.Config.kill_notifications_fully_enabled?()

    Logger.debug("[Pipeline] Notifications enabled: #{enabled}")

    enabled
  end

  @spec system_tracked?(integer() | nil) :: {:ok, boolean()} | {:error, term()}
  defp system_tracked?(nil), do: {:ok, false}

  defp system_tracked?(system_id) when is_integer(system_id) do
    system_id_str = Integer.to_string(system_id)
    Logger.info("[Pipeline] Checking if system #{system_id_str} is tracked")

    # In API mode, use the reverse index for efficient system tracking lookup.
    # In legacy mode, fall back to unscoped cache check.
    tracked = system_tracked_by_mode?(system_id_str)
    Logger.info("[Pipeline] System #{system_id_str} tracked check result: #{tracked}")
    {:ok, tracked}
  end

  defp system_tracked_by_mode?(system_id_str) do
    case map_registry().mode() do
      :api ->
        map_registry().maps_tracking_system(system_id_str) != []

      :legacy ->
        case WandererNotifier.Domains.Tracking.MapTrackingClient.is_system_tracked?(system_id_str) do
          {:ok, tracked} ->
            tracked

          {:error, reason} ->
            Logger.warning("[Pipeline] System tracking check failed for #{system_id_str}",
              reason: inspect(reason)
            )

            false
        end
    end
  end

  @spec character_tracked?(Killmail.t()) :: {:ok, boolean()} | {:error, term()}
  defp character_tracked?(%Killmail{} = killmail) do
    victim_tracked = victim_tracked?(killmail.victim_character_id)
    attacker_tracked = any_attacker_tracked?(killmail.attackers)

    if victim_tracked or attacker_tracked do
      Logger.debug(
        "[Pipeline] Killmail #{killmail.killmail_id} - victim: #{victim_tracked}, attacker: #{attacker_tracked}"
      )
    end

    {:ok, victim_tracked or attacker_tracked}
  end

  defp victim_tracked?(nil), do: false

  defp victim_tracked?(character_id) when is_integer(character_id) do
    character_id_str = Integer.to_string(character_id)
    Logger.info("[Pipeline] Checking if victim character #{character_id_str} is tracked")

    tracked = character_tracked_by_mode?(character_id_str)

    Logger.info(
      "[Pipeline] Victim character #{character_id_str} tracked check result: #{tracked}"
    )

    tracked
  end

  defp any_attacker_tracked?(nil), do: false

  defp any_attacker_tracked?(attackers) do
    Enum.any?(attackers, &attacker_tracked?/1)
  end

  defp attacker_tracked?(%{"character_id" => character_id}) when is_integer(character_id) do
    character_id |> Integer.to_string() |> character_tracked_by_mode?()
  end

  defp attacker_tracked?(%{"character_id" => character_id}) when is_binary(character_id) do
    character_tracked_by_mode?(character_id)
  end

  defp attacker_tracked?(_), do: false

  defp character_tracked_by_mode?(character_id_str) do
    case map_registry().mode() do
      :api ->
        map_registry().maps_tracking_character(character_id_str) != []

      :legacy ->
        case WandererNotifier.Domains.Tracking.MapTrackingClient.is_character_tracked?(
               character_id_str
             ) do
          {:ok, tracked} ->
            tracked

          {:error, reason} ->
            Logger.warning("[Pipeline] Character tracking check failed for #{character_id_str}",
              reason: inspect(reason)
            )

            false
        end
    end
  end

  @spec send_notification(Killmail.t()) :: result()
  defp send_notification(%Killmail{} = killmail) do
    Logger.info("[Pipeline] Starting notification process for killmail #{killmail.killmail_id}")

    # Corporation exclusion is now handled at the channel routing level in DiscordNotifier
    # to only exclude from system kill channel, not all notifications
    check_timing_and_notify(killmail)
  end

  @spec check_timing_and_notify(Killmail.t()) :: result()
  defp check_timing_and_notify(%Killmail{} = killmail) do
    # Check if we're in startup suppression period
    in_suppression = in_startup_suppression_period?()
    Logger.info("[Pipeline] Startup suppression check: #{in_suppression}")

    if in_suppression do
      Logger.info(
        "[Pipeline] Kill notification suppressed during startup period - killmail_id: #{killmail.killmail_id}"
      )

      handle_skipped(killmail.killmail_id, :startup_suppression)
    else
      # Check if killmail is too old
      Logger.info("[Pipeline] Checking killmail age for #{killmail.killmail_id}")

      case check_killmail_age(killmail) do
        :ok ->
          Logger.info("[Pipeline] Killmail age OK, proceeding to process_and_notify")
          process_and_notify(killmail)

        {:too_old, age_seconds} ->
          Logger.info(
            "[Pipeline] Kill notification suppressed - killmail too old",
            killmail_id: killmail.killmail_id,
            age_seconds: age_seconds,
            kill_time: killmail.kill_time
          )

          handle_skipped(killmail.killmail_id, :too_old)
      end
    end
  end

  defp process_and_notify(killmail) do
    # Process items right before sending notification (after we've decided to notify)
    killmail_to_notify =
      case maybe_process_items(killmail) do
        {:ok, enriched} ->
          notable_count = length(enriched.notable_items || [])
          dropped_count = length(enriched.items_dropped || [])

          Logger.info(
            "[NotableLoot] Item processing completed - killmail_id: #{killmail.killmail_id}, " <>
              "items_dropped: #{dropped_count}, notable_items: #{notable_count}"
          )

          enriched

        {:error, reason} ->
          Logger.warning(
            "[NotableLoot] Item processing failed, continuing without items - killmail_id: #{killmail.killmail_id}, reason: #{inspect(reason)}"
          )

          killmail
      end

    handle_notification_response(killmail_to_notify)
  end

  @spec handle_notification_response(Killmail.t()) :: result()
  defp handle_notification_response(%Killmail{} = killmail) do
    case map_registry().mode() do
      :api -> handle_api_notification(killmail)
      :legacy -> handle_legacy_notification(killmail)
    end
  end

  defp handle_api_notification(%Killmail{} = killmail) do
    map_count = fan_out_to_maps(killmail)

    if map_count == 0 do
      Telemetry.processing_completed(killmail.killmail_id, {:ok, :skipped})
      Telemetry.processing_skipped(killmail.killmail_id, :no_matching_maps)
      {:ok, :skipped}
    else
      Telemetry.processing_completed(killmail.killmail_id, {:ok, :notified})
      Telemetry.killmail_notified(killmail.killmail_id, killmail.system_name)
      Logger.debug("Killmail #{killmail.killmail_id} notification queued", category: :killmail)
      {:ok, killmail.killmail_id}
    end
  end

  defp handle_legacy_notification(%Killmail{} = killmail) do
    case send_legacy_notification(killmail) do
      {:ok, _pid} ->
        Telemetry.processing_completed(killmail.killmail_id, {:ok, :notified})
        Telemetry.killmail_notified(killmail.killmail_id, killmail.system_name)
        Logger.debug("Killmail #{killmail.killmail_id} notification queued", category: :killmail)
        {:ok, killmail.killmail_id}

      {:error, reason} ->
        Logger.error("[Pipeline] Failed to start legacy notification task",
          killmail_id: killmail.killmail_id,
          reason: inspect(reason)
        )

        Telemetry.processing_completed(killmail.killmail_id, {:ok, :skipped})
        Telemetry.processing_skipped(killmail.killmail_id, :notification_task_failed)
        {:ok, :skipped}
    end
  end

  # Multi-map fan-out: notify each map that tracks this system or involved characters.
  # Returns the count of maps where notification tasks were successfully started.
  defp fan_out_to_maps(%Killmail{} = killmail) do
    matching_maps = collect_matching_maps(killmail)
    map_count = length(matching_maps)

    Logger.info("[Pipeline] Fan-out: #{map_count} maps for killmail",
      killmail_id: killmail.killmail_id,
      system_id: killmail.system_id,
      map_count: map_count
    )

    Enum.count(matching_maps, &start_map_notification_task(killmail, &1))
  end

  defp start_map_notification_task(killmail, map_config) do
    case Task.Supervisor.start_child(WandererNotifier.TaskSupervisor, fn ->
           WandererNotifier.DiscordNotifier.send_kill_async(killmail, map_config)
         end) do
      {:ok, _pid} ->
        true

      {:error, reason} ->
        Logger.error("[Pipeline] Failed to start notification task",
          killmail_id: killmail.killmail_id,
          system_id: killmail.system_id,
          map_slug: map_config.slug,
          reason: inspect(reason)
        )

        false
    end
  end

  # Collect all unique maps that care about this killmail (by system or character)
  defp collect_matching_maps(%Killmail{} = killmail) do
    system_maps = map_registry().maps_tracking_system(killmail.system_id)
    character_maps = collect_character_maps(killmail)

    # Deduplicate by slug
    (system_maps ++ character_maps)
    |> Enum.uniq_by(& &1.slug)
  end

  defp collect_character_maps(%Killmail{} = killmail) do
    character_ids = extract_all_character_ids(killmail)

    Enum.flat_map(character_ids, fn id ->
      map_registry().maps_tracking_character(id)
    end)
  end

  defp extract_all_character_ids(%Killmail{} = killmail) do
    victim_ids =
      if killmail.victim_character_id,
        do: [to_string(killmail.victim_character_id)],
        else: []

    attacker_ids =
      (killmail.attackers || [])
      |> Enum.map(&Map.get(&1, "character_id"))
      |> Enum.reject(&is_nil/1)
      |> Enum.map(&to_string/1)

    (victim_ids ++ attacker_ids) |> Enum.uniq()
  end

  # Legacy single-map notification (existing behavior).
  # Returns {:ok, pid} or {:error, reason} from Task.Supervisor.start_child.
  @spec send_legacy_notification(Killmail.t()) :: {:ok, pid()} | {:error, term()}
  defp send_legacy_notification(%Killmail{} = killmail) do
    Task.Supervisor.start_child(WandererNotifier.TaskSupervisor, fn ->
      WandererNotifier.DiscordNotifier.send_kill_async(killmail)
    end)
  end

  # ═══════════════════════════════════════════════════════════════════════════════
  # Result Handlers
  # ═══════════════════════════════════════════════════════════════════════════════

  @spec handle_skipped(String.t(), atom()) :: result()
  defp handle_skipped(kill_id, reason) do
    Telemetry.processing_completed(kill_id, {:ok, :skipped})
    Telemetry.processing_skipped(kill_id, reason)

    reason_text = reason |> Atom.to_string() |> String.replace("_", " ")
    Logger.debug("Killmail #{kill_id} skipped: #{reason_text}", category: :killmail)

    {:ok, :skipped}
  end

  @spec handle_skipped_with_details(String.t(), atom(), Killmail.t()) :: result()
  defp handle_skipped_with_details(kill_id, reason, %Killmail{} = killmail) do
    Telemetry.processing_completed(kill_id, {:ok, :skipped})
    Telemetry.processing_skipped(kill_id, reason)

    reason_text = reason |> Atom.to_string() |> String.replace("_", " ")

    victim_name = killmail.victim_character_name || "Unknown"
    system_name = killmail.system_name

    Logger.debug(
      "Killmail #{kill_id} skipped: #{reason_text} - system: #{killmail.system_id}/#{system_name}, victim: #{killmail.victim_character_id}/#{victim_name}, corp: #{killmail.victim_corporation_name}, alliance: #{killmail.victim_alliance_name}, attackers: #{length(killmail.attackers || [])}"
    )

    {:ok, :skipped}
  end

  @spec handle_error(String.t(), term()) :: result()
  defp handle_error(kill_id, reason) do
    Telemetry.processing_completed(kill_id, {:error, reason})
    Telemetry.processing_error(kill_id, reason)

    Logger.error("Killmail #{kill_id} processing failed - error: #{inspect(reason)}")

    {:error, reason}
  end

  # ═══════════════════════════════════════════════════════════════════════════════
  # Item Processing
  # ═══════════════════════════════════════════════════════════════════════════════

  @spec maybe_process_items(Killmail.t()) :: {:ok, Killmail.t()} | {:error, term()}
  defp maybe_process_items(%Killmail{} = killmail) do
    enabled = Config.notable_items_enabled?()
    token_present = Config.janice_api_token() != nil

    Logger.info(
      "[NotableLoot] Item processing check - killmail_id: #{killmail.killmail_id}, " <>
        "notable_items_enabled: #{enabled}, janice_token_present: #{token_present}"
    )

    if enabled and token_present do
      Logger.info(
        "[NotableLoot] Starting item processing for killmail_id: #{killmail.killmail_id}"
      )

      ItemProcessor.process_killmail_items(killmail)
    else
      # Skip item processing if feature is disabled or Janice API token not configured
      reason =
        cond do
          not enabled -> "notable items feature disabled (set NOTABLE_ITEMS_ENABLED=true)"
          not token_present -> "no Janice API token configured (set JANICE_API_TOKEN)"
          true -> "unknown reason"
        end

      Logger.info(
        "[NotableLoot] Item processing skipped - #{reason} (killmail_id: #{killmail.killmail_id})"
      )

      {:ok, killmail}
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════════
  # Startup Suppression Check
  # ═══════════════════════════════════════════════════════════════════════════════

  defp in_startup_suppression_period?, do: Startup.in_suppression_period?()

  defp check_killmail_age(%Killmail{kill_time: nil}), do: :ok

  defp check_killmail_age(%Killmail{kill_time: kill_time}) do
    case TimeUtils.parse_iso8601(kill_time) do
      {:ok, kill_datetime} ->
        max_age_seconds = Config.max_killmail_age_seconds()

        if TimeUtils.within_age?(kill_datetime, max_age_seconds) do
          :ok
        else
          age_seconds = TimeUtils.elapsed_seconds(kill_datetime)
          {:too_old, age_seconds}
        end

      {:error, _reason} ->
        # If we can't parse the kill time, allow it through
        Logger.warning("Failed to parse kill_time", kill_time: kill_time)
        :ok
    end
  end
end
