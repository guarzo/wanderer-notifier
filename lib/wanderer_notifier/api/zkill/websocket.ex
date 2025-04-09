defmodule WandererNotifier.Api.ZKill.Websocket do
  @moduledoc """
  WebSocket client for zKillboard's WebSocket API.

  - Immediately subscribes upon connection by scheduling a :subscribe message
  - Uses heartbeat (pong) response after receiving a ping
  - Returns {:reconnect, state} on disconnect to leverage built-in auto-reconnect
  """
  use WebSockex
  alias WandererNotifier.Api.ESI.Service, as: ESIService
  alias WandererNotifier.Core.Stats
  alias WandererNotifier.KillmailProcessing.Pipeline
  alias WandererNotifier.Logger.Logger, as: AppLogger
  alias WandererNotifier.Resources.KillmailPersistence

  @doc false
  def init_batch_logging do
    AppLogger.init_batch_logger()
  end

  # Get config at runtime instead of compile time
  def get_config do
    Application.get_env(:wanderer_notifier, :websocket, [])
  end

  def default_url, do: get_config()[:url] || "wss://zkillboard.com/websocket/"
  def max_reconnects, do: get_config()[:max_reconnects] || 20
  def reconnect_window, do: get_config()[:reconnect_window] || 3600

  def start_link(parent, url \\ nil) do
    # Initialize batch logging for websocket events
    init_batch_logging()

    # Enhanced logging for WebSocket connection attempt
    url = url || default_url()
    AppLogger.websocket_info("Starting WebSocket connection", url: url)

    # Start the WebSocket connection
    case WebSockex.start_link(
           url,
           __MODULE__,
           %{
             parent: parent,
             connected: false,
             reconnects: 0,
             reconnect_history: [],
             circuit_open: false,
             last_circuit_reset: System.os_time(:second),
             url: url,
             startup_time: System.os_time(:second)
           },
           retry_initial_connection: true
         ) do
      {:ok, pid} ->
        AppLogger.websocket_info("🔌 WebSocket connected successfully")
        {:ok, pid}

      {:error, reason} ->
        AppLogger.websocket_error("❌ Connection failed", error: inspect(reason))
        {:error, reason}
    end
  end

  def init(state) do
    AppLogger.websocket_info("Initializing WebSocket client", url: state.url)

    # Add configuration values to state
    state =
      Map.merge(state, %{
        max_reconnects: max_reconnects(),
        reconnect_window: reconnect_window()
      })

    # Set application-level status for monitoring
    update_startup_status()

    # Schedule the initial heartbeat check
    Process.send_after(self(), :check_heartbeat, 60_000)

    {:ok, state}
  end

  # Helper to update status at startup
  defp update_startup_status do
    Stats.update_websocket(%{
      connected: false,
      connecting: true,
      startup_time: DateTime.utc_now(),
      last_message: nil,
      reconnects: 0,
      url: default_url()
    })

    :ok
  rescue
    # Stats service may not be ready yet
    e ->
      AppLogger.websocket_warn("Stats service not ready for status update",
        error: Exception.message(e)
      )

      :ok
  catch
    kind, error ->
      AppLogger.websocket_warn("Stats service not ready for status update", error: {kind, error})
      :ok
  end

  @impl true
  def handle_connect(_conn, state) do
    AppLogger.websocket_info("Connected to killstream websocket")
    now = DateTime.utc_now()

    # Set startup time if not already set
    startup_time = state.startup_time || System.os_time(:second)
    # Ensure it's a DateTime object for Stats
    startup_time_dt =
      if is_integer(startup_time) do
        DateTime.from_unix!(startup_time)
      else
        startup_time
      end

    new_state = %{state | connected: true, startup_time: startup_time}

    # Update websocket status with complete information
    Stats.update_websocket(%{
      connected: true,
      connecting: false,
      last_message: now,
      startup_time: startup_time_dt,
      reconnects: new_state.reconnects,
      url: new_state.url,
      last_disconnect: nil
    })

    # Schedule subscription message to avoid calling self
    Process.send_after(self(), :subscribe, 100)

    # Return OK immediately
    {:ok, new_state}
  end

  # Handle subscribe message
  @impl true
  def handle_info(:subscribe, state) do
    msg = Jason.encode!(%{"action" => "sub", "channel" => "killstream"})
    AppLogger.websocket_info("Subscribing to killstream channel")

    # Send the subscription frame
    {:reply, {:text, msg}, state}
  end

  # Handle heartbeat check message
  @impl true
  def handle_info(:check_heartbeat, state) do
    # Get last message time from state or Stats
    stats = Stats.get_stats()
    last_message_time = stats.websocket.last_message

    # Check if we've received any messages in the last 5 minutes
    now = DateTime.utc_now()

    no_messages =
      case last_message_time do
        nil -> true
        # 5 minutes
        time -> DateTime.diff(now, time, :second) > 300
      end

    if no_messages && state.connected do
      # No messages for too long, connection might be stale
      AppLogger.websocket_warn("No messages received in over 5 minutes",
        status: "connection_stale"
      )

      # Send a test ping to verify connection
      AppLogger.websocket_debug("Sending manual ping to test connection")

      case WebSockex.send_frame(self(), :ping) do
        :ok ->
          AppLogger.websocket_debug("Manual ping sent successfully")

        {:error, reason} ->
          AppLogger.websocket_error("Failed to send manual ping", error: inspect(reason))
          # Connection is definitely bad, initiate a reconnect
          Process.send_after(self(), :force_reconnect, 1000)
      end
    else
      # Use batch logging for routine heartbeat checks
      AppLogger.count_batch_event(:websocket_heartbeat, %{status: "ok"})
    end

    # Schedule the next heartbeat check
    # Check every minute
    Process.send_after(self(), :check_heartbeat, 60_000)
    {:ok, state}
  end

  # Handle reconnect request
  @impl true
  def handle_info(:force_reconnect, state) do
    AppLogger.websocket_warn("Forcing reconnection", reason: "heartbeat_failure")
    # This will trigger the disconnect handler which will reconnect
    {:close, state}
  end

  @impl true
  def handle_frame(frame, state) do
    case frame do
      # Text frames - handle JSON messages
      {:text, raw_msg} ->
        process_text_frame(raw_msg, state)

      # Binary frames - just log the size
      {:binary, data} ->
        # Use batch logging for binary frames
        AppLogger.count_batch_event(:websocket_binary_frame, %{size_bytes: byte_size(data)})
        {:ok, state}

      # Ping frames - send heartbeat response
      {:ping, ping_frame} ->
        handle_ping_frame(ping_frame, state)

      # Any other frame type
      _ ->
        AppLogger.websocket_debug("Received unexpected frame type", frame: inspect(frame))
        {:ok, state}
    end
  rescue
    e ->
      AppLogger.websocket_error("Error processing frame",
        error: Exception.message(e),
        stacktrace: Exception.format_stacktrace(__STACKTRACE__)
      )

      {:ok, state}
  end

  # Helper to handle ping frames
  defp handle_ping_frame(ping_frame, state) do
    # Standard ping format is "ping"
    is_standard = ping_frame == "ping"

    # Use batch logging for normal pings
    if is_standard do
      AppLogger.count_batch_event(:websocket_ping, %{format: "standard"})
    else
      AppLogger.websocket_debug("Received non-standard ping", content: inspect(ping_frame))
    end

    # Send heartbeat immediately
    payload = Jason.encode!(%{"action" => "pong"})
    {:reply, {:text, payload}, state}
  end

  # Process text frames containing JSON data
  defp process_text_frame(frame, state) do
    case decode_frame(frame) do
      {:ok, decoded} -> handle_decoded_frame(decoded, state)
      {:error, reason} -> handle_decode_error(reason, frame, state)
    end
  end

  defp decode_frame(frame) do
    Jason.decode(frame)
  rescue
    e -> {:error, {e, frame}}
  end

  defp handle_decoded_frame(decoded, state) when is_map(decoded) do
    case extract_killmail_info(decoded) do
      {:ok, killmail_info} -> process_killmail(killmail_info, state)
      {:error, reason} -> handle_killmail_error(reason, decoded, state)
    end
  end

  defp handle_decoded_frame(decoded, state) do
    log_unexpected_frame_format(decoded)
    {:ok, state}
  end

  defp extract_killmail_info(decoded) do
    with {:ok, killmail_id} <- extract_killmail_id(decoded),
         {:ok, hash} <- extract_hash(decoded) do
      {:ok, %{killmail_id: killmail_id, hash: hash}}
    end
  end

  defp extract_killmail_id(%{"killmail_id" => id}) when is_integer(id), do: {:ok, id}
  defp extract_killmail_id(decoded), do: {:error, {:missing_killmail_id, decoded}}

  defp extract_hash(%{"hash" => hash}) when is_binary(hash), do: {:ok, hash}
  defp extract_hash(decoded), do: {:error, {:missing_hash, decoded}}

  defp process_killmail(%{killmail_id: killmail_id, hash: hash}, state) do
    case check_killmail_status(killmail_id) do
      :not_processed -> handle_new_killmail(killmail_id, hash, state)
      :already_processed -> handle_duplicate_killmail(killmail_id, state)
      {:error, reason} -> handle_status_check_error(reason, killmail_id, state)
    end
  end

  defp check_killmail_status(killmail_id) do
    case KillmailPersistence.check_killmail_exists_in_database(killmail_id, nil, nil) do
      true -> :already_processed
      false -> :not_processed
    end
  rescue
    e ->
      AppLogger.websocket_error("[ZKill] Error checking killmail status", %{
        killmail_id: killmail_id,
        error: Exception.message(e)
      })

      {:error, e}
  end

  defp handle_new_killmail(killmail_id, hash, state) do
    log_new_killmail(killmail_id)

    case fetch_and_process_killmail(killmail_id, hash) do
      :ok -> {:ok, increment_processed_count(state)}
      {:error, reason} -> handle_processing_error(reason, killmail_id, state)
    end
  end

  defp fetch_and_process_killmail(killmail_id, hash) do
    with {:ok, killmail} <- ESIService.get_killmail(killmail_id, hash),
         :ok <- Pipeline.process_killmail(killmail, nil) do
      :ok
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp handle_duplicate_killmail(killmail_id, state) do
    log_duplicate_killmail(killmail_id)
    {:ok, increment_duplicate_count(state)}
  end

  defp handle_status_check_error(reason, killmail_id, state) do
    log_status_check_error(reason, killmail_id)
    {:ok, increment_error_count(state)}
  end

  defp handle_killmail_error(reason, decoded, state) do
    log_killmail_error(reason, decoded)
    {:ok, increment_error_count(state)}
  end

  defp handle_decode_error(reason, frame, state) do
    log_decode_error(reason, frame)
    {:ok, increment_error_count(state)}
  end

  defp log_unexpected_frame_format(decoded) do
    AppLogger.websocket_warn("[ZKill] Received unexpected frame format", %{
      frame: inspect(decoded)
    })
  end

  defp log_new_killmail(killmail_id) do
    AppLogger.websocket_debug("[ZKill] Processing new killmail", %{
      killmail_id: killmail_id
    })
  end

  defp log_duplicate_killmail(killmail_id) do
    AppLogger.websocket_debug("[ZKill] Skipping duplicate killmail", %{
      killmail_id: killmail_id
    })
  end

  defp log_status_check_error(reason, killmail_id) do
    AppLogger.websocket_error("[ZKill] Error checking killmail status", %{
      killmail_id: killmail_id,
      error: inspect(reason)
    })
  end

  defp log_killmail_error(reason, decoded) do
    AppLogger.websocket_error("[ZKill] Invalid killmail data format", %{
      error: inspect(reason),
      data: inspect(decoded)
    })
  end

  defp log_decode_error(reason, frame) do
    AppLogger.websocket_error("[ZKill] Failed to decode websocket frame", %{
      error: inspect(reason),
      frame: inspect(frame)
    })
  end

  defp increment_processed_count(state) do
    update_in(state.processed_count, &(&1 + 1))
  end

  defp increment_duplicate_count(state) do
    update_in(state.duplicate_count, &(&1 + 1))
  end

  defp increment_error_count(state) do
    update_in(state.error_count, &(&1 + 1))
  end

  defp handle_processing_error(reason, killmail_id, state) do
    AppLogger.websocket_error("[ZKill] Failed to process killmail", %{
      killmail_id: killmail_id,
      error: inspect(reason)
    })

    {:ok, increment_error_count(state)}
  end

  @impl true
  def handle_disconnect(disconnect_map, state) do
    # Update reconnect count and check for circuit breaking condition
    new_state =
      state
      |> increment_reconnect_count
      |> check_circuit_breaker

    if new_state.circuit_open do
      # Circuit is open, stop reconnection attempts
      AppLogger.websocket_error("Circuit breaker open, reconnection stopped",
        reason: inspect(disconnect_map),
        reconnect_count: new_state.reconnects
      )

      # Update status to show permanent disconnection
      Stats.update_websocket(%{
        connected: false,
        connecting: false,
        last_message: state.last_message,
        startup_time: ensure_datetime(state.startup_time),
        reconnects: new_state.reconnects,
        url: state.url,
        last_disconnect: DateTime.utc_now()
      })

      {:error, new_state}
    else
      # Circuit is closed, attempt reconnection
      delay = calculate_reconnect_delay(new_state.reconnects)

      AppLogger.websocket_warn("Disconnected, reconnecting",
        reason: inspect(disconnect_map),
        reconnect_attempts: new_state.reconnects,
        delay_ms: delay
      )

      # Update application status to show disconnection with reconnect pending
      Stats.update_websocket(%{
        connected: false,
        connecting: true,
        last_message: state.last_message,
        startup_time: ensure_datetime(state.startup_time),
        reconnects: new_state.reconnects,
        url: state.url,
        last_disconnect: DateTime.utc_now()
      })

      # Request reconnection after a delay
      {:reconnect, %{new_state | connected: false}}
    end
  end

  # Increment reconnect count and add timestamp to history
  defp increment_reconnect_count(state) do
    current_time = System.os_time(:second)

    # Add current time to reconnect history
    new_history = [current_time | state.reconnect_history]

    # Keep only reconnects within the monitoring window
    window_start = current_time - state.reconnect_window
    filtered_history = Enum.filter(new_history, fn time -> time >= window_start end)

    %{state | reconnects: state.reconnects + 1, reconnect_history: filtered_history}
  end

  # Check if circuit breaker should open based on reconnection frequency
  defp check_circuit_breaker(state) do
    # Count recent reconnects in our monitoring window
    current_time = System.os_time(:second)
    recent_reconnects = Enum.count(state.reconnect_history)
    time_since_reset = current_time - state.last_circuit_reset

    # If we have too many recent reconnects, open the circuit
    # But only if it's been at least 10 minutes since last reset
    # 10 minutes
    should_open_circuit =
      recent_reconnects >= max_reconnects() &&
        time_since_reset >= 600

    if should_open_circuit do
      AppLogger.websocket_error("Circuit breaker triggered",
        reconnect_count: recent_reconnects,
        minutes_since_reset: Float.round(time_since_reset / 60, 1)
      )

      %{state | circuit_open: true}
    else
      # If it's been a long time since last reset (24h+), reset the counter
      if time_since_reset >= 86_400 do
        AppLogger.websocket_info("Resetting circuit breaker",
          previous_reconnect_count: state.reconnects
        )

        %{state | reconnects: 0, last_circuit_reset: current_time}
      else
        state
      end
    end
  end

  # Calculate exponential backoff delay for reconnection
  defp calculate_reconnect_delay(reconnect_count) do
    # Base delay is 500ms
    base_delay = 500
    # Use exponential backoff with jitter
    delay = :math.pow(1.5, min(reconnect_count, 10)) * base_delay
    # Add some random jitter (±25%)
    jitter = :rand.uniform() * 0.5 - 0.25
    delay_with_jitter = delay * (1 + jitter)
    # Cap at 2 minutes
    trunc(min(delay_with_jitter, 120_000))
  end

  # Terminate the process
  @impl true
  def terminate(reason, state) do
    AppLogger.websocket_info("WebSocket terminating",
      reason: inspect(reason),
      connected: state.connected,
      reconnects: state.reconnects,
      circuit_open: state.circuit_open
    )

    # No special cleanup needed
    :ok
  end

  # Helper to ensure a timestamp is converted to DateTime
  defp ensure_datetime(nil), do: DateTime.utc_now()
  defp ensure_datetime(%DateTime{} = dt), do: dt
  defp ensure_datetime(timestamp) when is_integer(timestamp), do: DateTime.from_unix!(timestamp)
  defp ensure_datetime(_), do: DateTime.utc_now()
end
