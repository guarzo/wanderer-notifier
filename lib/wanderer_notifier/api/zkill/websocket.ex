defmodule WandererNotifier.Api.ZKill.Websocket do
  @moduledoc """
  WebSocket client for zKillboard's WebSocket API.

  - Immediately subscribes upon connection by scheduling a :subscribe message
  - Uses heartbeat (pong) response after receiving a ping
  - Returns {:reconnect, state} on disconnect to leverage built-in auto-reconnect
  """
  use WebSockex
  require Logger
  alias WandererNotifier.Core.Stats

  # Maximum reconnection attempts before circuit breaking
  @max_reconnects 20
  # Time window to monitor reconnects (in seconds)
  @reconnect_window 3600

  def start_link(parent, url) do
    # Enhanced logging for WebSocket connection attempt
    Logger.info("Starting zKillboard WebSocket connection to #{url}")

    # Set application-level status for monitoring
    update_startup_status()

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
        Logger.info("Successfully initialized zKillboard WebSocket with PID: #{inspect(pid)}")
        {:ok, pid}

      {:error, reason} ->
        Logger.error("Failed to start websocket: #{inspect(reason)}")
        {:error, reason}
    end
  end

  def init(state) do
    Logger.info("Initializing zKill WebSocket client. Will attempt connection to #{state.url}")
    # Report initial state
    Stats.update_websocket(%{
      connected: false,
      connecting: true,
      last_message: nil,
      reconnects: 0,
      url: state.url
    })

    # Schedule the initial heartbeat check
    Process.send_after(self(), :check_heartbeat, 60_000)

    {:ok, state}
  end

  # Helper to update status at startup
  defp update_startup_status do
    try do
      Stats.update_websocket(%{
        connected: false,
        connecting: true,
        startup_time: DateTime.utc_now(),
        last_message: nil
      })
    rescue
      e -> Logger.error("Failed to update startup status: #{inspect(e)}")
    end
  end

  @impl true
  def handle_connect(_conn, state) do
    Logger.info("Connected to zKill websocket.")
    new_state = Map.put(state, :connected, true)

    # Update websocket status
    update_connection_status(new_state)

    # Schedule subscription message to avoid calling self
    Process.send_after(self(), :subscribe, 100)

    # Return OK immediately
    {:ok, new_state}
  end

  # Helper function to update connection status
  defp update_connection_status(state) do
    try do
      Stats.update_websocket(%{
        connected: true,
        last_message: DateTime.utc_now(),
        reconnects: Map.get(state, :reconnects, 0)
      })
    rescue
      e -> Logger.error("Failed to update websocket status: #{inspect(e)}")
    end
  end

  # Handle subscribe message
  @impl true
  def handle_info(:subscribe, state) do
    msg = Jason.encode!(%{"action" => "sub", "channel" => "killstream"})
    Logger.info("Subscribing to zKillboard killstream channel with message: #{msg}")

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
      Logger.warning("No WebSocket messages received in over 5 minutes. Connection may be stale.")

      # Send a test ping to verify connection
      Logger.info("Sending manual ping to test WebSocket connection")

      case WebSockex.send_frame(self(), :ping) do
        :ok ->
          Logger.debug("Manual ping sent successfully")

        {:error, reason} ->
          Logger.error("Failed to send manual ping: #{inspect(reason)}")
          # Connection is definitely bad, initiate a reconnect
          Process.send_after(self(), :force_reconnect, 1000)
      end
    else
      Logger.debug("WebSocket heartbeat check passed")
    end

    # Schedule the next heartbeat check
    # Check every minute
    Process.send_after(self(), :check_heartbeat, 60_000)
    {:ok, state}
  end

  # Handle reconnect request
  @impl true
  def handle_info(:force_reconnect, state) do
    Logger.warning("Forcing WebSocket reconnection due to heartbeat failure")
    # This will trigger the disconnect handler which will reconnect
    {:close, state}
  end

  @impl true
  def handle_frame(frame, state) do
    try do
      case frame do
        # Text frames - handle JSON messages
        {:text, raw_msg} ->
          process_text_frame(raw_msg, state)

        # Binary frames - just log the size
        {:binary, data} ->
          Logger.debug("Received binary frame from zKill (#{byte_size(data)} bytes)")
          {:ok, state}

        # Ping frames - send heartbeat response
        {:ping, ping_frame} ->
          handle_ping_frame(ping_frame, state)

        # Any other frame type
        _ ->
          Logger.debug("Received unexpected frame type from zKill: #{inspect(frame)}")
          {:ok, state}
      end
    rescue
      e ->
        Logger.error("Error in handle_frame/2: #{inspect(e)}")
        {:ok, state}
    end
  end

  # Helper to handle ping frames
  defp handle_ping_frame(ping_frame, state) do
    ping_log_message =
      if ping_frame == "ping" do
        "Received WS ping from zKill"
      else
        "Received unexpected ping format from zKill: #{inspect(ping_frame)}"
      end

    Logger.debug("#{ping_log_message}. Sending heartbeat pong response.")

    # Send heartbeat immediately
    payload = Jason.encode!(%{"action" => "pong"})
    {:reply, {:text, payload}, state}
  end

  # Process text frames containing JSON data
  defp process_text_frame(raw_msg, state) do
    # Update timestamp of last received message for monitoring
    now = DateTime.utc_now()

    try do
      Stats.update_websocket(%{
        connected: true,
        last_message: now,
        reconnects: Map.get(state, :reconnects, 0)
      })
    rescue
      e -> Logger.error("Failed to update websocket status: #{inspect(e)}")
    end

    case Jason.decode(raw_msg, keys: :strings) do
      {:ok, json_data} ->
        # Log the type of message (debug level to avoid excessive logging)
        message_type = classify_message_type(json_data)
        Logger.debug("Processed killstream message of type: #{message_type}")

        # Forward to parent process for handling
        if is_pid(state.parent) and Process.alive?(state.parent) do
          Logger.debug("Forwarding zKill message to parent process")
          send(state.parent, {:zkill_message, raw_msg})
          {:ok, state}
        else
          Logger.warning("Parent process not available or not alive, skipping message")
          {:ok, state}
        end

      {:error, decode_err} ->
        Logger.error("Error decoding zKill frame: #{inspect(decode_err)}. Raw: #{raw_msg}")
        {:ok, state}
    end
  end

  # Identify the message type for better logging
  defp classify_message_type(json_data) when is_map(json_data) do
    cond do
      Map.has_key?(json_data, "action") ->
        "action:#{json_data["action"]}"

      Map.has_key?(json_data, "killmail_id") and Map.has_key?(json_data, "zkb") ->
        "killmail_with_zkb"

      Map.has_key?(json_data, "killmail_id") ->
        "killmail_without_zkb"

      Map.has_key?(json_data, "kill_id") ->
        "kill_info"

      Map.has_key?(json_data, "tqStatus") ->
        "tq_status"

      true ->
        "unknown"
    end
  end

  defp classify_message_type(_), do: "non_map"

  @impl true
  def handle_pong({:pong, data}, state) do
    Logger.debug("Received WS pong from zKill: #{inspect(data)}")
    {:ok, state}
  end

  @impl true
  def handle_disconnect(disconnect_info, state) do
    # Record disconnect time for circuit breaker
    current_time = System.os_time(:second)

    # Add disconnect to history
    history =
      [current_time | state.reconnect_history]
      |> Enum.filter(fn time -> current_time - time < @reconnect_window end)

    # Update reconnect count
    reconnects = Map.get(state, :reconnects, 0) + 1

    # Check if circuit breaker should trip
    circuit_state = check_circuit_breaker(history, state, current_time)

    # Update state with new values
    new_state =
      state
      |> Map.put(:reconnects, reconnects)
      |> Map.put(:reconnect_history, history)
      |> Map.put(:circuit_open, circuit_state.circuit_open)
      |> Map.put(:last_circuit_reset, circuit_state.last_reset)

    # Format disconnect message
    disconnect_message = format_disconnect_message(disconnect_info)

    Logger.warning(
      "zKill websocket disconnected: #{disconnect_message}. #{circuit_state.message}"
    )

    # Update stats
    try do
      Stats.update_websocket(%{
        connected: false,
        last_message: DateTime.utc_now(),
        reconnects: reconnects,
        circuit_open: circuit_state.circuit_open
      })
    rescue
      _ -> :ok
    end

    {:reconnect, new_state}
  end

  # Format disconnect message for easier reading
  defp format_disconnect_message(disconnect_info) do
    case disconnect_info do
      %{code: code, reason: reason} ->
        "code=#{inspect(code)}, reason=#{inspect(reason)}"

      other ->
        inspect(other)
    end
  end

  # Determine if circuit breaker should be open or closed
  defp check_circuit_breaker(history, state, current_time) do
    # Count recent disconnects
    recent_disconnects = length(history)

    # Reset circuit breaker after a period if it was open
    circuit_open =
      if state.circuit_open && current_time - state.last_circuit_reset > @reconnect_window do
        # Reset after window has passed
        false
      else
        # Check if we need to open the circuit
        recent_disconnects > @max_reconnects || state.circuit_open
      end

    # Determine appropriate message and delay
    {message, delay, last_reset} =
      cond do
        circuit_open && !state.circuit_open ->
          # Circuit just opened
          {
            "Circuit breaker engaged after #{recent_disconnects} disconnects in #{@reconnect_window}s",
            # 2 minute delay before retry
            120_000,
            current_time
          }

        circuit_open ->
          # Circuit was already open
          {
            "Circuit breaker remains open, limiting reconnection attempts",
            # 5 minute delay
            300_000,
            state.last_circuit_reset
          }

        true ->
          # Circuit closed, normal operation
          {"Reconnecting...", 0, state.last_circuit_reset}
      end

    %{
      circuit_open: circuit_open,
      message: message,
      delay: delay,
      last_reset: last_reset
    }
  end

  @impl true
  def terminate(reason, _state) do
    Logger.warning("ZKill websocket terminating: #{inspect(reason)}")
    :ok
  end
end
