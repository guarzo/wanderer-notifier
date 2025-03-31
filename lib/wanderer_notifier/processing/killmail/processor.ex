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

  alias WandererNotifier.Config.Features
  alias WandererNotifier.Data.Killmail
  alias WandererNotifier.Logger.Logger, as: AppLogger
  alias WandererNotifier.Notifiers.Determiner
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

    AppLogger.kill_info(
      "📥 WEBSOCKET KILL RECEIVED: Processing killmail #{kill_id} in system #{system_id}",
      %{
        kill_id: kill_id,
        system_id: system_id,
        message_type: "killmail"
      }
    )

    # Debug K-space tracking for common systems
    debug_kspace_system_tracking(system_id)

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

        # The rest is treated as ESI data, removing zkb key
        esi_data = Map.drop(killmail, ["zkb"])

        # Create a Killmail struct to standardize the data structure
        killmail_struct = Killmail.new(kill_id, zkb_data, esi_data)

        # Print the tracking status for this kill to check if K-space tracking is working
        Determiner.print_system_tracking_status()

        # Process the standardized data
        process_new_kill(killmail_struct, kill_id, state)
    end
  end

  # Debug K-space tracking for common systems
  defp debug_kspace_system_tracking(system_id) do
    # Check if this is a K-space system (IDs from 30000000 to 31000000)
    case Integer.parse(to_string(system_id)) do
      {id, _} when id >= 30_000_000 and id < 31_000_000 ->
        AppLogger.kill_info("🔬 Testing K-space tracking for system #{system_id}")

        # Check this specific system
        Determiner.debug_kspace_tracking(system_id)

        # Also check some common K-space systems for comparison
        # Jita, Amarr, Perimeter
        common_systems = ["30000142", "30002187", "30000144"]

        for test_id <- common_systems, test_id != to_string(system_id) do
          Determiner.debug_kspace_tracking(test_id)
        end

      _ ->
        # Not a K-space system ID or invalid
        :ok
    end
  end

  defp process_new_kill(%Killmail{} = killmail, kill_id, state) do
    AppLogger.kill_info(
      "⚙️ PROCESSING KILL #{kill_id}: Starting full kill processing flow",
      %{
        kill_id: kill_id,
        system_id: get_in(killmail.esi_data || %{}, ["solar_system_id"]),
        notification_decision_pending: true
      }
    )

    # Store the kill in the cache
    Cache.cache_kill(killmail.killmail_id, killmail)

    # Persist killmail if the feature is enabled and related to tracked character
    persist_result = persist_killmail_synchronously(killmail)

    # Log the persistence result
    case persist_result do
      {:ok, _} ->
        AppLogger.kill_info("Successfully persisted killmail", kill_id: kill_id)

      :ignored ->
        AppLogger.kill_debug("Killmail #{kill_id} not relevant for persistence, ignoring")

      {:error, reason} ->
        AppLogger.kill_error("Error persisting killmail #{kill_id}: #{inspect(reason)}")
    end

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
    AppLogger.kill_info(
      "🔔 NOTIFICATION PROCESS: Determining if kill #{kill_id} should be notified",
      %{
        kill_id: kill_id,
        system_id: get_in(killmail.esi_data || %{}, ["solar_system_id"]),
        system_name: get_in(killmail.esi_data || %{}, ["solar_system_name"]),
        character_tracking_enabled: Features.character_tracking_enabled?(),
        system_tracking_enabled: Features.system_tracking_enabled?(),
        track_kspace_enabled: Features.track_kspace_systems?()
      }
    )

    # Process the kill for notification
    notification_result = Enrichment.process_and_notify(killmail)

    # Properly handle all possible return types
    case notification_result do
      :ok ->
        AppLogger.kill_info(
          "✅ NOTIFICATION DECISION COMPLETE: Kill #{kill_id} was processed successfully",
          %{
            kill_id: kill_id,
            result: :ok,
            processing_completed: true
          }
        )

        # Mark kill as processed in state
        Map.update(state, :processed_kill_ids, %{kill_id => :os.system_time(:second)}, fn ids ->
          Map.put(ids, kill_id, :os.system_time(:second))
        end)

      # The :error case is not actually possible since process_and_notify always returns :ok
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

  # Helper to get system ID from killmail
  defp get_kill_system_id(killmail) when is_map(killmail) do
    system_id =
      Map.get(killmail, "solar_system_id") ||
        (killmail["zkb"] && killmail["zkb"]["system_id"]) ||
        "unknown"

    to_string(system_id)
  end

  defp get_kill_system_id(_), do: "unknown"
end
