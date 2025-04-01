defmodule WandererNotifier.Processing.Killmail.Processor do
  @moduledoc """
  Processes killmail data from various sources.
  This module is responsible for analyzing killmail data, determining what actions
  to take, and orchestrating notifications as needed.

  This is the main entry point for killmail processing and coordinates between specialized modules:
  - Stats: Tracks and reports statistics about processed kills
  - Enrichment: Adds additional data to killmails
  - Notification: Handles notification decisions and dispatch
  - Cache: Manages caching of killmail data
  """

  require Logger

  alias WandererNotifier.Api.ESI.Service, as: ESIService
  alias WandererNotifier.Data.Killmail
  alias WandererNotifier.Logger.Logger, as: AppLogger
  alias WandererNotifier.Processing.Killmail.{Cache, Enrichment, Notification, Stats}
  alias WandererNotifier.Resources.KillmailPersistence

  @doc """
  Initializes all killmail processing components.
  Should be called at application startup.
  """
  def init do
    Stats.init()
    Cache.init()
  end

  @doc """
  Schedules periodic tasks such as stats logging.
  """
  def schedule_tasks do
    Stats.schedule_logging()
  end

  @doc """
  Logs kill statistics.
  Called periodically to report stats about processed kills.
  """
  def log_stats do
    Stats.log()
  end

  @doc """
  Processes a websocket message from zKillboard.
  Handles both text and map messages, routing them to the appropriate handlers.

  Returns an updated state that tracks processed kills.
  """
  def process_zkill_message(message, state) when is_binary(message) do
    AppLogger.websocket_debug("Processing WebSocket message", bytes_size: byte_size(message))

    case Jason.decode(message) do
      {:ok, decoded_message} ->
        process_zkill_message(decoded_message, state)

      {:error, reason} ->
        AppLogger.websocket_error("Failed to decode WebSocket message", error: inspect(reason))
        state
    end
  end

  def process_zkill_message(message, state) when is_map(message) do
    # Determine message type based on structure
    cond do
      # TQ server status message
      Map.has_key?(message, "action") && message["action"] == "tqStatus" ->
        handle_tq_status(message)
        state

      # Killmail message - identified by either killmail_id or zkb key
      Map.has_key?(message, "killmail_id") || Map.has_key?(message, "zkb") ->
        # Update statistics for kill received
        Stats.update(:kill_received)
        handle_killmail(message, state)

      # Unknown message type
      true ->
        AppLogger.websocket_warn("Ignoring unknown message type",
          message_keys: Map.keys(message)
        )

        state
    end
  end

  @doc """
  Gets a list of recent kills from the cache.
  """
  def get_recent_kills do
    Cache.get_recent_kills()
  end

  @doc """
  Sends a test kill notification using recent data.
  """
  def send_test_kill_notification do
    Notification.send_test()
  end

  # Private functions

  defp handle_tq_status(%{"tqStatus" => %{"players" => player_count, "vip" => vip}}) do
    # Store in process dictionary for now, we could use the state or a separate GenServer later
    Process.put(:tq_status, %{
      player_count: player_count,
      vip: vip,
      timestamp: :os.system_time(:second)
    })

    AppLogger.websocket_debug("Received TQ status update",
      players_online: player_count,
      vip_mode: vip
    )
  end

  defp handle_tq_status(_status) do
    AppLogger.websocket_warn("Received malformed TQ status message")
  end

  defp handle_killmail(killmail, state) do
    # Extract the kill ID
    kill_id = get_killmail_id(killmail)

    # Extract basic info for logging
    system_id = get_kill_system_id(killmail)

    # Get system name for enhanced logging
    system_name =
      case ESIService.get_system_info(system_id) do
        {:ok, system_info} -> Map.get(system_info, "name", "Unknown")
        _ -> "Unknown"
      end

    AppLogger.kill_info(
      "📥 WEBSOCKET KILL RECEIVED: Processing killmail #{kill_id} in system #{system_name} (#{system_id})",
      %{
        kill_id: kill_id,
        system_id: system_id,
        system_name: system_name,
        message_type: "killmail"
      }
    )

    # Skip processing if no kill ID or already processed
    cond do
      is_nil(kill_id) ->
        AppLogger.kill_warn("Received killmail without kill ID")
        state

      Map.has_key?(state.processed_kill_ids, kill_id) ->
        AppLogger.kill_debug("Kill #{kill_id} already processed, skipping")
        state

      true ->
        # Process the new kill - first standardize to Killmail struct
        AppLogger.kill_debug("Processing new kill #{kill_id}")

        # Extract zkb data
        zkb_data = Map.get(killmail, "zkb", %{})

        # The rest is treated as ESI data, removing zkb key and ensuring system ID is in correct format
        esi_data =
          killmail
          |> Map.drop(["zkb"])
          |> Map.put("solar_system_id", system_id)
          |> Map.put("solar_system_name", system_name)

        # Create a Killmail struct to standardize the data structure
        killmail_struct = Killmail.new(kill_id, zkb_data, esi_data)

        # Process the standardized data
        process_new_kill(killmail_struct, kill_id, state)
    end
  end

  defp process_new_kill(%Killmail{} = killmail, kill_id, state) do
    # Store the kill in the cache
    Cache.cache_kill(killmail.killmail_id, killmail)

    # Persist killmail if the feature is enabled and related to tracked character
    persist_result = persist_killmail_synchronously(killmail)

    # Only continue with notification if persistence succeeded or was ignored
    # This ensures database and notifications stay in sync
    case persist_result do
      {:ok, _} ->
        process_killmail_notification(killmail, kill_id, state)

      :ignored ->
        # For ignored killmails (not relevant to tracked characters), we still notify
        process_killmail_notification(killmail, kill_id, state)

      {:error, _} ->
        # If persistence failed, we don't notify
        # This prevents notifications for data that wasn't persisted
        AppLogger.kill_warn(
          "Skipping notification for killmail #{kill_id} due to persistence failure"
        )

        state
    end
  end

  # Helper function to handle killmail persistence synchronously
  defp persist_killmail_synchronously(killmail) do
    result = KillmailPersistence.maybe_persist_killmail(killmail)
    # Properly handle all possible return types
    case result do
      {:ok, record} when is_map(record) or is_struct(record) ->
        # Normal success case with a record
        {:ok, record}

      {:ok, nil} ->
        # Success with no data
        {:ok, :persisted_with_no_data}

      {:ok, other} ->
        # Any other successful result
        AppLogger.kill_debug("Persistence returned unexpected success format: #{inspect(other)}")
        {:ok, :persisted}

      :ignored ->
        # Ignored case
        :ignored

      {:error, reason} ->
        # Error case
        {:error, reason}

      unexpected ->
        # Handle truly unexpected return values
        AppLogger.kill_warn("Persistence returned unexpected format: #{inspect(unexpected)}")
        {:ok, :persisted_with_unexpected_response}
    end
  rescue
    e ->
      AppLogger.kill_error("Error in persistence: #{Exception.message(e)}")
      AppLogger.kill_debug("Stacktrace: #{Exception.format_stacktrace()}")
      {:error, Exception.message(e)}
  end

  # Helper function to process killmail notification
  defp process_killmail_notification(killmail, kill_id, state) do
    # Process the kill for notification
    notification_result = Enrichment.process_and_notify(killmail)

    # Properly handle all possible return types
    case notification_result do
      :ok ->
        # Mark kill as processed in state
        Map.update(state, :processed_kill_ids, %{kill_id => :os.system_time(:second)}, fn ids ->
          Map.put(ids, kill_id, :os.system_time(:second))
        end)

      {:ok, :skipped} ->
        # Kill was intentionally skipped, still mark as processed
        Map.update(state, :processed_kill_ids, %{kill_id => :os.system_time(:second)}, fn ids ->
          Map.put(ids, kill_id, :os.system_time(:second))
        end)

      # The :error case is not actually possible since process_and_notify always returns :ok or {:ok, :skipped}
      # but we keep it for future-proofing in case the implementation changes
      other ->
        # Handle any other unexpected return type
        AppLogger.kill_warn(
          "Unexpected return from notification for kill #{kill_id}: #{inspect(other)}"
        )

        state
    end
  end

  # Helper function to extract the killmail ID from different possible structures
  defp get_killmail_id(kill_data) when is_map(kill_data) do
    # Based on the standard zKillboard websocket format, the killmail_id should be directly
    # available as a field named "killmail_id". If not, try to extract from the zkb data.
    kill_data["killmail_id"] ||
      (kill_data["zkb"] && kill_data["zkb"]["killID"])
  end

  defp get_killmail_id(_), do: nil

  # Helper to try different paths for system ID
  defp try_system_id_paths(killmail) do
    [
      # Direct solar_system_id field
      Map.get(killmail, "solar_system_id"),
      # ESI data path
      get_in(killmail, ["esi_data", "solar_system_id"]),
      # ZKB data path
      get_in(killmail, ["zkb", "system_id"]),
      # System object path
      get_in(killmail, ["system", "id"]),
      # Solar system object path
      get_in(killmail, ["solar_system", "id"])
    ]
    |> Enum.find(& &1)
  end

  # Helper to format system ID
  defp format_system_id(nil), do: "unknown"
  defp format_system_id(id) when is_integer(id), do: to_string(id)
  defp format_system_id(id) when is_binary(id), do: id
  defp format_system_id(_), do: "unknown"

  # Helper to get system ID from killmail
  defp get_kill_system_id(killmail) when is_map(killmail) do
    killmail
    |> try_system_id_paths()
    |> format_system_id()
  end

  defp get_kill_system_id(_), do: "unknown"
end
