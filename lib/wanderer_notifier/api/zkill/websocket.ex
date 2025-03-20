defmodule WandererNotifier.Api.ZKill.Websocket do
  @moduledoc """
  WebSocket client for zKillboard's WebSocket API.

  - Immediately subscribes upon connection by scheduling a :subscribe message.
  - Uses a scheduled heartbeat (pong) response after receiving a ping.
  - Returns {:reconnect, state} on disconnect to leverage built-in auto-reconnect.
  """
  use WebSockex
  require Logger
  alias WandererNotifier.Config.Timings
  alias WandererNotifier.Services.KillProcessor
  alias WandererNotifier.Core.Stats

  # Maximum reconnection attempts before circuit breaking
  @max_reconnects 20
  # Time window to monitor reconnects (in seconds)
  # 1 hour
  @reconnect_window 3600

  def start_link(parent, url) do
    # Enhanced logging for WebSocket connection attempt
    Logger.info("Starting zKillboard WebSocket connection to #{url}")
    
    # Set application-level status for monitoring
    update_startup_status()
    
    # Run in spawn_link for better exception handling during startup
    result = WebSockex.start_link(url, __MODULE__, %{
      parent: parent,
      connected: false,
      reconnects: 0,
      reconnect_history: [],
      circuit_open: false,
      last_circuit_reset: System.os_time(:second),
      url: url,  # Store URL for reconnection reference
      startup_time: System.os_time(:second)
    }, [retry_initial_connection: true])
    
    # Log the connection result
    case result do
      {:ok, pid} ->
        Logger.info("Successfully initialized zKillboard WebSocket with PID: #{inspect(pid)}")
        # Return the result
        result
        
      {:error, reason} ->
        Logger.error("Failed to connect to zKillboard WebSocket: #{inspect(reason)}")
        # Try to recover with a delayed restart
        Process.sleep(5000)  # Wait 5 seconds
        # Return the original error to avoid masking issues
        result
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

    # Update websocket status - wrapped in a function to isolate error handling
    update_connection_status(new_state)

    # Schedule subscription so that send_frame is not called within handle_connect
    Process.send_after(self(), :subscribe, 0)
    {:ok, new_state}
  end

  # Helper function to update connection status with isolated error handling
  defp update_connection_status(state) do
    try do
      Stats.update_websocket(%{
        connected: true,
        last_message: DateTime.utc_now(),
        reconnects: Map.get(state, :reconnects, 0)
      })
    rescue
      e ->
        Logger.error("Failed to update websocket status: #{inspect(e)}")
        :error
    catch
      kind, reason ->
        Logger.error("Caught #{kind} updating websocket status: #{inspect(reason)}")
        :error
    end
  end

  @impl true
  def handle_info(message, state) do
    case message do
      :subscribe ->
        if state.circuit_open do
          Logger.warning("Circuit breaker open - skipping subscription attempt")
          {:ok, state}
        else
          subscribe_to_killstream(state)
        end

      :heartbeat ->
        payload = Jason.encode!(%{"action" => "pong"})
        Logger.debug("Sending heartbeat pong with payload: #{payload}")
        {:reply, {:text, payload}, state}

      # Catch-all for any other info messages - categorized by message pattern
      _ ->
        case categorize_message(message) do
          :telemetry ->
            # Silently handle telemetry events
            {:ok, state}

          :internal ->
            # Log internal messages at debug level
            Logger.debug("Internal message in ZKill.Websocket: #{inspect(message)}")
            {:ok, state}

          :unknown ->
            # Log truly unknown messages at warning level
            Logger.warning("Unhandled message in ZKill.Websocket: #{inspect(message)}")
            {:ok, state}
        end
    end
  end

  defp subscribe_to_killstream(state) do
    msg = Jason.encode!(%{"action" => "sub", "channel" => "killstream"})
    Logger.debug("Subscribing to killstream with message: #{msg}")

    # Use Task.Supervisor for safer async operations
    # Don't pass self() to the task - this is causing the CallingSelfError
    case start_supervised_task(fn ->
           # Use direct send to the parent process instead of WebSockex.send_frame
           try do
             # Use separate process to send the frame
             parent = self()

             spawn(fn ->
               case WebSockex.send_frame(parent, {:text, msg}) do
                 :ok ->
                   Logger.debug("Subscription message sent successfully.")

                 {:error, error} ->
                   Logger.error("Failed to send subscription message: #{inspect(error)}")
               end
             end)
           rescue
             e -> Logger.error("Error sending subscription: #{inspect(e)}")
           catch
             kind, reason ->
               Logger.error("Caught #{kind} sending subscription: #{inspect(reason)}")
           end
         end) do
      {:ok, _task} ->
        Logger.debug("Subscription task started")
        {:ok, state}

      {:error, reason} ->
        Logger.error("Failed to start subscription task: #{inspect(reason)}")
        {:ok, state}
    end
  end

  defp start_supervised_task(fun) do
    # Get the application-wide Task.Supervisor or fall back to direct Task
    case Process.whereis(WandererNotifier.TaskSupervisor) do
      nil ->
        # Fallback to direct Task if supervisor not available
        {:ok, Task.start(fun)}

      supervisor ->
        Task.Supervisor.start_child(supervisor, fun)
    end
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

        # Ping frames - schedule a heartbeat response
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
    catch
      kind, reason ->
        Logger.error("Caught #{kind} in handle_frame/2: #{inspect(reason)}")
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

    Logger.debug(
      "#{ping_log_message}. Scheduling heartbeat pong in #{Timings.websocket_heartbeat_interval()}ms."
    )

    Process.send_after(self(), :heartbeat, Timings.websocket_heartbeat_interval())
    {:ok, state}
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
    
    # Log more verbosely to help with troubleshooting
    log_level = if String.length(raw_msg) > 500, do: :debug, else: :info
    Logger.log(log_level, "Received killstream frame at #{DateTime.to_string(now)}: #{raw_msg}")

    case Jason.decode(raw_msg, keys: :strings) do
      {:ok, json_data} ->
        # Log the type of message for troubleshooting
        message_type = classify_message_type(json_data)
        Logger.info("Processed killstream message of type: #{message_type}")
        handle_json_message(json_data, raw_msg, state)

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

  # Process different types of JSON messages
  defp handle_json_message(json_data, raw_msg, state) do
    case classify_json_message(json_data) do
      {:killmail_with_zkb, kill_id, zkb_info} ->
        # Standard killmail with zkb data
        log_killmail(kill_id, zkb_info)
        forward_to_parent(state.parent, raw_msg, json_data, state)

      {:killmail_without_zkb, kill_id} ->
        # Killmail without zkb data
        Logger.debug("Received killmail without zkb data: kill_id=#{kill_id}")
        forward_to_parent(state.parent, raw_msg, json_data, state)

      {:kill_info, kill_id, system_id} ->
        # Kill info message
        Logger.debug("Received kill info: kill_id=#{kill_id}, system_id=#{system_id}")
        forward_to_parent(state.parent, raw_msg, json_data, state)

      {:action, action} ->
        # Action message (ping, etc.)
        Logger.debug("Received action message: #{action}")
        {:ok, state}

      :unknown ->
        # Unrecognized message format
        Logger.debug("Received unrecognized killstream JSON: #{inspect(json_data)}")
        forward_to_parent(state.parent, raw_msg, json_data, state)
    end
  end

  # Classify different JSON message types
  defp classify_json_message(json_data) do
    cond do
      # Killmail with zkb data
      is_map_key(json_data, "killmail_id") and is_map_key(json_data, "zkb") ->
        {:killmail_with_zkb, json_data["killmail_id"], json_data["zkb"]}

      # Killmail without zkb data
      is_map_key(json_data, "killmail_id") ->
        {:killmail_without_zkb, json_data["killmail_id"]}

      # Kill info message
      is_map_key(json_data, "kill_id") ->
        {:kill_info, json_data["kill_id"], Map.get(json_data, "solar_system_id")}

      # Action message
      is_map_key(json_data, "action") ->
        {:action, json_data["action"]}

      # Unknown message format
      true ->
        :unknown
    end
  end

  # Log killmail details with truncated zkb info
  defp log_killmail(kill_id, zkb_info) do
    truncated_zkb = truncate_for_logging(zkb_info)

    Logger.debug(
      "[ZKill.Websocket] Received kill partial: killmail_id=#{kill_id} zkb=#{truncated_zkb}"
    )
  end

  # Forward message to parent process or process directly
  defp forward_to_parent(parent, raw_msg, json_data, state) do
    if is_pid(parent) and Process.alive?(parent) do
      Logger.debug("Forwarding zKill message to parent process #{inspect(parent)}")
      
      # Enhanced message forwarding with better error handling and logging
      try do
        # Extract the killmail ID for logging if available
        kill_id = extract_kill_id(json_data)
        id_log = if kill_id, do: " (ID: #{kill_id})", else: ""
        
        Logger.info("Forwarding killmail message#{id_log} to parent process")
        send(parent, {:zkill_message, raw_msg})
        
        # Track this in stats
        update_kill_forwarded_stats()
        
        {:ok, state}
      rescue
        e ->
          Logger.error("Error forwarding message to parent: #{inspect(e)}")
          {:ok, state}
      end
    else
      # If parent process is not available, process directly
      Logger.warning("Parent process not available or not alive, processing kill directly")
      try_direct_processing(json_data, state)
    end
  end

  # Helper to extract kill ID for logging
  defp extract_kill_id(json_data) do
    cond do
      is_map_key(json_data, "killmail_id") -> json_data["killmail_id"]
      is_map_key(json_data, "kill_id") -> json_data["kill_id"]
      true -> nil
    end
  end
  
  # Update stats about forwarded kill messages
  defp update_kill_forwarded_stats do
    try do
      stats = Stats.get_stats()
      # Track time of last forwarded message in websocket stats
      Stats.update_websocket(Map.put(stats.websocket, :last_forwarded, DateTime.utc_now()))
    rescue
      _ -> :ok
    end
  end

  # Attempt direct processing of messages if parent is unavailable
  defp try_direct_processing(json_data, state) do
    # Enhanced error handling and message typechecking
    try do
      if is_map_key(json_data, "killmail_id") do
        Logger.info("Directly processing kill ID #{json_data["killmail_id"]}")
        KillProcessor.process_zkill_message(json_data, %{})
        {:ok, state}
      else
        kill_type = classify_message_type(json_data)
        Logger.info("Skipping direct processing for non-killmail message of type #{kill_type}")
        {:ok, state}
      end
    rescue
      e ->
        Logger.error("Error in direct kill processing: #{inspect(e)}")
        {:ok, state}
    end
  end

  @impl true
  def handle_pong({:pong, data}, state) do
    Logger.debug("Received WS pong from zKill: #{inspect(data)}")
    {:ok, state}
  end

  @impl true
  def handle_cast(msg, state) do
    Logger.debug("Unhandled cast in ZKill.Websocket: #{inspect(msg)}")
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

    if circuit_state.circuit_open do
      # Circuit breaker tripped - delay reconnection attempt
      Process.send_after(self(), :subscribe, circuit_state.delay)
      {:reconnect, new_state}
    else
      # Normal reconnect
      {:reconnect, new_state}
    end
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

  # Helper function for logging that handles various data types
  defp truncate_for_logging(data) when is_map(data) do
    # Extract only essential information if it's a zkb map
    if Map.has_key?(data, "totalValue") do
      # It's a zkb info map
      essential_keys = ["totalValue", "url", "locationID"]
      truncated_map = Map.take(data, essential_keys)

      # Add a note about truncated fields
      truncated_count = map_size(data) - map_size(truncated_map)

      result =
        if truncated_count > 0 do
          Map.put(truncated_map, "_truncated", "#{truncated_count} fields omitted")
        else
          truncated_map
        end

      inspect(result, limit: 5)
    else
      # Regular map
      inspect(data, limit: 5)
    end
  end

  defp truncate_for_logging(other) do
    # For any other data type
    inspect(other, limit: 5)
  end

  # Helper to categorize messages for better logging
  defp categorize_message(message) do
    cond do
      # Telemetry events
      match?({:telemetry_event, _, _, _}, message) ->
        :telemetry

      # Internal process messages
      is_tuple(message) and tuple_size(message) > 0 and
          elem(message, 0) in [:DOWN, :EXIT, :process_metrics] ->
        :internal

      # Everything else is unknown
      true ->
        :unknown
    end
  end
end
