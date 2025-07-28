defmodule WandererNotifier.Domains.Killmail.Pipeline do
  @moduledoc """
  Simplified unified pipeline for processing killmails.

  Merges the functionality of Pipeline and Processor modules to eliminate duplication.
  Handles pre-enriched WebSocket data directly without unnecessary transformations.
  """

  require Logger
  alias WandererNotifier.Application.Telemetry
  alias WandererNotifier.Domains.Killmail.Killmail
  alias WandererNotifier.Domains.Notifications.Deduplication
  alias WandererNotifier.Infrastructure.Cache

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

    try do
      with {:ok, :new} <- check_deduplication(kill_id),
           {:ok, %Killmail{} = killmail} <- build_killmail(killmail_data),
           {:ok, true} <- should_notify?(killmail) do
        send_notification(killmail)
      else
        {:ok, :duplicate} ->
          handle_skipped(kill_id, :duplicate)

        {:ok, false} ->
          handle_skipped(kill_id, :not_tracked)

        {:error, reason} ->
          handle_error(kill_id, reason)
      end
    rescue
      exception ->
        Logger.error("Pipeline crash",
          kill_id: kill_id,
          error: inspect(exception),
          category: :killmail
        )

        handle_error(kill_id, {:unexpected_error, exception})
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

  @spec check_deduplication(String.t()) :: {:ok, :new | :duplicate} | {:error, term()}
  defp check_deduplication(kill_id) do
    case Deduplication.check(:kill, kill_id) do
      {:ok, :new} -> {:ok, :new}
      {:ok, :duplicate} -> {:ok, :duplicate}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec build_killmail(killmail_data()) :: {:ok, Killmail.t()} | {:error, term()}
  defp build_killmail(data) do
    # Data from WebSocket is pre-enriched, so we can build directly
    kill_id = extract_kill_id(data)
    system_id = extract_system_id(data)

    Logger.info(
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

        Logger.info(
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
    Logger.info("[Pipeline] Notifications enabled: #{enabled}")

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
      Logger.info(
        "[Pipeline] Tracking check - System #{killmail.system_id}: #{system_tracked}, Characters: #{character_tracked}"
      )

      {:ok, system_tracked or character_tracked}
    end
  end

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

    Logger.info(
      "[Pipeline] Character tracking - Victim #{killmail.victim_character_id}: #{victim_tracked}, Any attacker: #{attacker_tracked}"
    )

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
    case WandererNotifier.Application.Services.NotificationService.notify_kill(killmail) do
      :ok ->
        Telemetry.processing_completed(killmail.killmail_id, {:ok, :notified})
        Telemetry.killmail_notified(killmail.killmail_id, killmail.system_name)
        Logger.info("Killmail #{killmail.killmail_id} notified", category: :killmail)
        {:ok, killmail.killmail_id}

      {:error, :notifications_disabled} ->
        handle_skipped(killmail.killmail_id, :notifications_disabled)

      {:error, reason} ->
        handle_error(killmail.killmail_id, reason)
    end
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
