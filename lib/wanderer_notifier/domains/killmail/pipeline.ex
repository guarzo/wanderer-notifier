defmodule WandererNotifier.Domains.Killmail.Pipeline do
  @moduledoc """
  Simplified unified pipeline for processing killmails.

  Merges the functionality of Pipeline and Processor modules to eliminate duplication.
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

  @type killmail_data :: map()
  @type result :: {:ok, String.t() | :skipped} | {:error, term()}

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
    # Deduplication already happens in WebSocket client
    with {:ok, %Killmail{} = killmail} <- build_killmail(killmail_data),
         {:ok, true} <- should_notify?(killmail) do
      send_notification(killmail)
    else
      {:ok, false} ->
        # Get killmail for logging details even though we're not notifying
        case build_killmail(killmail_data) do
          {:ok, %Killmail{} = killmail} ->
            handle_skipped_with_details(kill_id, :not_tracked, killmail)

          _ ->
            handle_skipped(kill_id, :not_tracked)
        end

      {:error, reason} ->
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

  @doc """
  Send a test notification using recent kill data.
  """
  @spec send_test_notification() :: result()
  def send_test_notification do
    case get_recent_kills() do
      {:ok, [kill_data | _]} ->
        Logger.info("Sending test notification", category: :killmail)
        process_killmail(kill_data)

      {:ok, []} ->
        {:error, :no_recent_kills}
    end
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

        Logger.debug(
          "[Pipeline] Built killmail - Victim ID: #{inspect(killmail.victim_character_id)}, Attackers: #{length(killmail.attackers || [])}"
        )

        {:ok, killmail}
    end
  end

  @spec extract_system_id(killmail_data()) :: integer() | nil
  defp extract_system_id(data) do
    possible_keys = ["system_id", :system_id, "solar_system_id", :solar_system_id]

    system_id =
      find_system_id_value(data, possible_keys) || get_in(data, ["killmail", "solar_system_id"])

    parse_system_id(system_id)
  end

  defp find_system_id_value(data, keys) do
    Enum.find_value(keys, fn key -> data[key] end)
  end

  defp parse_system_id(id) when is_integer(id), do: id

  defp parse_system_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {int_id, ""} -> int_id
      _ -> nil
    end
  end

  defp parse_system_id(_), do: nil

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
    with {:ok, system_tracked} <- system_tracked?(killmail.system_id),
         {:ok, character_tracked} <- character_tracked?(killmail) do
      _victim_name = killmail.victim_character_name || "Unknown"
      _system_name = killmail.system_name || "Unknown System"

      is_tracked = system_tracked or character_tracked
      log_tracking_status(killmail.killmail_id, system_tracked, character_tracked, is_tracked)

      {:ok, is_tracked}
    end
  end

  defp log_tracking_status(killmail_id, system_tracked, character_tracked, is_tracked) do
    if is_tracked do
      tracking_reason = get_tracking_reason(system_tracked, character_tracked)
      Logger.info("[Pipeline] Killmail #{killmail_id} tracked: #{tracking_reason}")
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
    notifications_enabled = WandererNotifier.Shared.Config.notifications_enabled?()
    kill_notifications_enabled = WandererNotifier.Shared.Config.kill_notifications_enabled?()

    Logger.debug(
      "[Pipeline] Config - notifications_enabled: #{notifications_enabled}, kill_notifications_enabled: #{kill_notifications_enabled}"
    )

    notifications_enabled and kill_notifications_enabled
  end

  @spec system_tracked?(integer() | nil) :: {:ok, boolean()} | {:error, term()}
  defp system_tracked?(nil), do: {:ok, false}

  defp system_tracked?(system_id) when is_integer(system_id) do
    system_id
    |> Integer.to_string()
    |> WandererNotifier.Domains.Tracking.MapTrackingClient.is_system_tracked?()
  end

  @spec character_tracked?(Killmail.t()) :: {:ok, boolean()} | {:error, term()}
  defp character_tracked?(%Killmail{} = killmail) do
    victim_tracked = victim_tracked?(killmail.victim_character_id)
    attacker_tracked = any_attacker_tracked?(killmail.attackers)

    _victim_name = killmail.victim_character_name || "Unknown"

    if victim_tracked or attacker_tracked do
      Logger.debug(
        "[Pipeline] Killmail #{killmail.killmail_id} - victim: #{victim_tracked}, attacker: #{attacker_tracked}"
      )
    end

    {:ok, victim_tracked or attacker_tracked}
  end

  defp victim_tracked?(nil), do: false

  defp victim_tracked?(character_id) when is_integer(character_id) do
    character_id
    |> Integer.to_string()
    |> WandererNotifier.Domains.Tracking.MapTrackingClient.is_character_tracked?()
    |> case do
      {:ok, true} -> true
      _ -> false
    end
  end

  defp any_attacker_tracked?(nil), do: false

  defp any_attacker_tracked?(attackers) do
    Enum.any?(attackers, &attacker_tracked?/1)
  end

  defp attacker_tracked?(%{"character_id" => character_id}) when is_integer(character_id) do
    character_id
    |> Integer.to_string()
    |> WandererNotifier.Domains.Tracking.MapTrackingClient.is_character_tracked?()
    |> case do
      {:ok, true} -> true
      _ -> false
    end
  end

  defp attacker_tracked?(%{"character_id" => character_id}) when is_binary(character_id) do
    case WandererNotifier.Domains.Tracking.MapTrackingClient.is_character_tracked?(character_id) do
      {:ok, true} -> true
      _ -> false
    end
  end

  defp attacker_tracked?(_), do: false

  @spec send_notification(Killmail.t()) :: result()
  defp send_notification(%Killmail{} = killmail) do
    Logger.debug("Sending kill notification", killmail_id: killmail.killmail_id)

    # Determine whether to process items based on startup suppression period
    killmail_to_notify =
      if in_startup_suppression_period?() do
        # Skip item processing entirely during startup suppression period
        killmail
      else
        # Process items right before sending notification (after we've decided to notify)
        case maybe_process_items(killmail) do
          {:ok, enriched} ->
            Logger.debug("Item processing completed successfully",
              killmail_id: killmail.killmail_id
            )

            enriched

          {:error, reason} ->
            Logger.warning("Item processing failed, continuing without items",
              killmail_id: killmail.killmail_id,
              reason: reason
            )

            killmail
        end
      end

    handle_notification_response(killmail_to_notify)
  end

  @spec handle_notification_response(Killmail.t()) :: result()
  defp handle_notification_response(%Killmail{} = killmail) do
    # Send kill notification directly - always returns :ok immediately
    WandererNotifier.DiscordNotifier.send_kill_async(killmail)

    # Always return success since we're using fire-and-forget async processing
    Telemetry.processing_completed(killmail.killmail_id, {:ok, :notified})
    Telemetry.killmail_notified(killmail.killmail_id, killmail.system_name)
    Logger.debug("Killmail #{killmail.killmail_id} notification queued", category: :killmail)
    {:ok, killmail.killmail_id}
  end

  # ═══════════════════════════════════════════════════════════════════════════════
  # Result Handlers
  # ═══════════════════════════════════════════════════════════════════════════════

  @spec handle_skipped(String.t(), atom()) :: result()
  defp handle_skipped(kill_id, reason) do
    Telemetry.processing_completed(kill_id, {:ok, :skipped})
    Telemetry.processing_skipped(kill_id, reason)

    reason_text = reason |> Atom.to_string() |> String.replace("_", " ")
    Logger.info("Killmail #{kill_id} skipped: #{reason_text}", category: :killmail)

    {:ok, :skipped}
  end

  @spec handle_skipped_with_details(String.t(), atom(), Killmail.t()) :: result()
  defp handle_skipped_with_details(kill_id, reason, %Killmail{} = killmail) do
    Telemetry.processing_completed(kill_id, {:ok, :skipped})
    Telemetry.processing_skipped(kill_id, reason)

    reason_text = reason |> Atom.to_string() |> String.replace("_", " ")

    victim_name =
      case killmail.victim_character_name do
        nil -> "Unknown"
        name -> name
      end

    system_name = killmail.system_name || "Unknown System"

    Logger.info("Killmail #{kill_id} skipped: #{reason_text}",
      category: :killmail,
      system_id: killmail.system_id,
      system_name: system_name,
      victim_id: killmail.victim_character_id,
      victim_name: victim_name,
      victim_corp: killmail.victim_corporation_name,
      victim_alliance: killmail.victim_alliance_name,
      attacker_count: length(killmail.attackers || [])
    )

    {:ok, :skipped}
  end

  @spec handle_error(String.t(), term()) :: result()
  defp handle_error(kill_id, reason) do
    Telemetry.processing_completed(kill_id, {:error, reason})
    Telemetry.processing_error(kill_id, reason)

    Logger.error("Killmail #{kill_id} processing failed",
      error: inspect(reason),
      category: :killmail
    )

    {:error, reason}
  end

  # ═══════════════════════════════════════════════════════════════════════════════
  # Item Processing
  # ═══════════════════════════════════════════════════════════════════════════════

  @spec maybe_process_items(Killmail.t()) :: {:ok, Killmail.t()} | {:error, term()}
  defp maybe_process_items(%Killmail{} = killmail) do
    enabled = Config.get(:notable_items_enabled, false)
    token_present = Config.get(:janice_api_token) != nil

    Logger.debug("Item processing status",
      killmail_id: killmail.killmail_id,
      notable_items_enabled: enabled,
      janice_token_present: token_present,
      category: :item_processing
    )

    if enabled and token_present do
      Logger.debug("Starting item processing", killmail_id: killmail.killmail_id)
      ItemProcessor.process_killmail_items(killmail)
    else
      # Skip item processing if feature is disabled or Janice API token not configured
      reason =
        cond do
          not enabled -> "notable items feature disabled"
          not token_present -> "no Janice API token configured"
          true -> "unknown reason"
        end

      Logger.debug("Item processing skipped - #{reason}",
        killmail_id: killmail.killmail_id
      )

      {:ok, killmail}
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════════
  # Startup Suppression Check
  # ═══════════════════════════════════════════════════════════════════════════════

  defp in_startup_suppression_period?, do: Startup.in_suppression_period?()

  # ═══════════════════════════════════════════════════════════════════════════════
  # Utilities
  # ═══════════════════════════════════════════════════════════════════════════════

  @spec get_recent_kills() :: {:ok, list(killmail_data())} | {:error, term()}
  defp get_recent_kills do
    case Cache.get("zkill:recent_kills") do
      {:ok, kills} when is_list(kills) -> {:ok, kills}
      {:error, :not_found} -> {:ok, []}
      _ -> {:ok, []}
    end
  end
end
