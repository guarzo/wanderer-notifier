defmodule WandererNotifier.Killmail.Websocket do
  @moduledoc """
  WebSocket client for zKillboard's WebSocket API.

  - Immediately subscribes upon connection by scheduling a :subscribe message
  - Uses heartbeat (pong) response after receiving a ping
  - Returns {:reconnect, state} on disconnect to leverage built-in auto-reconnect
  """
  use WebSockex
  alias WandererNotifier.Core.Stats
  alias WandererNotifier.Logger.Logger, as: AppLogger

  def init_batch_logging do
    AppLogger.init_batch_logger()
  end

  def get_config do
    Application.get_env(:wanderer_notifier, :websocket, [])
  end

  def default_url, do: get_config()[:url] || "wss://zkillboard.com/websocket/"
  def max_reconnects, do: get_config()[:max_reconnects] || 20
  def reconnect_window, do: get_config()[:reconnect_window] || 3600

  def start_link(parent, url \\ nil) do
    init_batch_logging()
    url = url || default_url()
    AppLogger.websocket_info("Starting WebSocket connection", url: url)

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

    state =
      Map.merge(state, %{
        max_reconnects: max_reconnects(),
        reconnect_window: reconnect_window()
      })

    update_startup_status()
    Process.send_after(self(), :check_heartbeat, 60_000)
    {:ok, state}
  end

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
    startup_time = state.startup_time || System.os_time(:second)
    new_state = %{state | connected: true, startup_time: startup_time}

    Stats.update_websocket(%{
      connected: true,
      connecting: false,
      last_message: now,
      startup_time: DateTime.from_unix!(startup_time),
      reconnects: new_state.reconnects,
      url: new_state.url,
      last_disconnect: nil
    })

    Process.send_after(self(), :subscribe, 100)
    {:ok, new_state}
  end

  @impl true
  def handle_info(:subscribe, state) do
    msg = Jason.encode!(%{"action" => "sub", "channel" => "killstream"})
    AppLogger.websocket_info("Subscribing to killstream channel")
    {:reply, {:text, msg}, state}
  end

  @impl true
  def handle_info(:check_heartbeat, state) do
    stats = Stats.get_stats()
    last_message_time = stats.websocket.last_message
    now = DateTime.utc_now()

    no_messages =
      case last_message_time do
        nil -> true
        time -> DateTime.diff(now, time, :second) > 300
      end

    if no_messages && state.connected do
      AppLogger.websocket_warn("No messages received in over 5 minutes",
        status: "connection_stale"
      )

      AppLogger.websocket_debug("Sending manual ping to test connection")

      case WebSockex.send_frame(self(), :ping) do
        :ok ->
          AppLogger.websocket_debug("Manual ping sent successfully")

        {:error, reason} ->
          AppLogger.websocket_error("Failed to send manual ping", error: inspect(reason))
          Process.send_after(self(), :force_reconnect, 1000)
      end
    else
      AppLogger.count_batch_event(:websocket_heartbeat, %{status: "ok"})
    end

    Process.send_after(self(), :check_heartbeat, 60_000)
    {:ok, state}
  end

  @impl true
  def handle_info(:force_reconnect, state) do
    AppLogger.websocket_warn("Forcing reconnection", reason: "heartbeat_failure")
    {:close, state}
  end

  @impl true
  def handle_frame(frame, state) do
    case frame do
      {:text, raw_msg} ->
        process_text_frame(raw_msg, state)

      {:binary, data} ->
        AppLogger.count_batch_event(:websocket_binary_frame, %{size_bytes: byte_size(data)})
        {:ok, state}

      {:ping, ping_frame} ->
        handle_ping_frame(ping_frame, state)

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

  defp handle_ping_frame(ping_frame, state) do
    is_standard = ping_frame == "ping"

    if is_standard do
      AppLogger.count_batch_event(:websocket_ping, %{format: "standard"})
    else
      AppLogger.websocket_debug("Received non-standard ping", content: inspect(ping_frame))
    end

    payload = Jason.encode!(%{"action" => "pong"})
    {:reply, {:text, payload}, state}
  end

  defp process_text_frame(raw_msg, state) do
    now = DateTime.utc_now()

    try do
      current_stats = Stats.get_stats()

      Stats.update_websocket(%{
        connected: true,
        connecting: false,
        last_message: now,
        startup_time: current_stats.websocket.startup_time || state.startup_time,
        reconnects: state.reconnects,
        url: state.url
      })
    rescue
      e ->
        AppLogger.websocket_error("Failed to update websocket status",
          error: Exception.message(e),
          stacktrace: Exception.format_stacktrace(__STACKTRACE__)
        )
    end

    case Jason.decode(raw_msg, keys: :strings) do
      {:ok, json_data} ->
        message_type = classify_message_type(json_data)
        AppLogger.count_batch_event(:websocket_message, %{type: message_type})

        if is_pid(state.parent) and Process.alive?(state.parent) do
          send(state.parent, {:zkill_message, raw_msg})
          {:ok, state}
        else
          AppLogger.websocket_warn("Parent process unavailable, message dropped")
          {:ok, state}
        end

      {:error, decode_err} ->
        AppLogger.websocket_error("Error decoding JSON frame",
          error: inspect(decode_err),
          raw_message: String.slice(raw_msg, 0, 100)
        )

        {:ok, state}
    end
  end

  defp classify_message_type(json_data) when is_map(json_data) do
    cond do
      Map.has_key?(json_data, "action") && json_data["action"] == "tqStatus" ->
        "tq_status"

      Map.has_key?(json_data, "zkb") ->
        "killmail"

      Map.has_key?(json_data, "killmail_id") ->
        "killmail"

      true ->
        "unknown"
    end
  end

  defp classify_message_type(_), do: "invalid"

  @impl true
  def handle_disconnect(disconnect_map, state) do
    new_state =
      state
      |> increment_reconnect_count
      |> check_circuit_breaker

    if new_state.circuit_open do
      AppLogger.websocket_error("Circuit breaker open, reconnection stopped",
        reason: inspect(disconnect_map),
        reconnect_count: new_state.reconnects
      )

      Stats.update_websocket(%{
        connected: false,
        connecting: false,
        last_message: state.last_message,
        startup_time: state.startup_time,
        reconnects: new_state.reconnects,
        url: state.url,
        last_disconnect: DateTime.utc_now()
      })

      {:error, new_state}
    else
      delay = calculate_reconnect_delay(new_state.reconnects)

      AppLogger.websocket_warn("Disconnected, reconnecting",
        reason: inspect(disconnect_map),
        reconnect_attempts: new_state.reconnects,
        delay_ms: delay
      )

      Stats.update_websocket(%{
        connected: false,
        connecting: true,
        last_message: state.last_message,
        startup_time: state.startup_time,
        reconnects: new_state.reconnects,
        url: state.url,
        last_disconnect: DateTime.utc_now()
      })

      {:reconnect, %{new_state | connected: false}}
    end
  end

  defp increment_reconnect_count(state) do
    current_time = System.os_time(:second)
    new_history = [current_time | state.reconnect_history]
    window_start = current_time - state.reconnect_window
    filtered_history = Enum.filter(new_history, fn time -> time >= window_start end)
    %{state | reconnects: state.reconnects + 1, reconnect_history: filtered_history}
  end

  defp check_circuit_breaker(state) do
    current_time = System.os_time(:second)
    recent_reconnects = Enum.count(state.reconnect_history)
    time_since_reset = current_time - state.last_circuit_reset

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

  defp calculate_reconnect_delay(reconnect_count) do
    base_delay = 500
    delay = :math.pow(1.5, min(reconnect_count, 10)) * base_delay
    jitter = :rand.uniform() * 0.5 - 0.25
    delay_with_jitter = delay * (1 + jitter)
    trunc(min(delay_with_jitter, 120_000))
  end

  @impl true
  def terminate(reason, state) do
    AppLogger.websocket_info("WebSocket terminating",
      reason: inspect(reason),
      connected: state.connected,
      reconnects: state.reconnects,
      circuit_open: state.circuit_open
    )

    :ok
  end
end
