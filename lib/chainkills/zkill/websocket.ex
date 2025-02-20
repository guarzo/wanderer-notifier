defmodule ChainKills.ZKill.Websocket do
  @moduledoc """
  WebSockex client connecting to zKill's killstream.

  - Immediately subscribes upon connection by scheduling a :subscribe message.
  - Uses a scheduled heartbeat (pong) response after receiving a ping.
  - Returns {:reconnect, state} on disconnect to leverage built-in auto-reconnect.
  """
  use WebSockex
  require Logger

  @heartbeat_interval 10_000

  def start_link(parent, url) do
    WebSockex.start_link(url, __MODULE__, %{parent: parent, connected: false})
  end

  def init(state) do
    Logger.info("Initializing zKill websocket client.")
    {:ok, state}
  end

  @impl true
  def handle_connect(_conn, state) do
    Logger.info("Connected to zKill websocket.")
    new_state = Map.put(state, :connected, true)
    # Schedule subscription so that send_frame is not called within handle_connect
    Process.send_after(self(), :subscribe, 0)
    {:ok, new_state}
  end

  @impl true
  def handle_info(:subscribe, state) do
    msg = Jason.encode!(%{"action" => "sub", "channel" => "killstream"})
    Logger.debug("Subscribing to killstream with message: #{msg}")
    ws_pid = self()

    # Spawn a task but wrap the call in a try/rescue so errors don't crash the websocket.
    Task.start(fn ->
      try do
        case WebSockex.send_frame(ws_pid, {:text, msg}) do
          :ok ->
            Logger.debug("Subscription message sent successfully.")
          {:error, error} ->
            Logger.error("Failed to send subscription message: #{inspect(error)}")
        end
      rescue
        e ->
          Logger.error("Error in subscription task: #{inspect(e)}")
      end
    end)

    {:ok, state}
  end

  def handle_info(:heartbeat, state) do
    payload = Jason.encode!(%{"action" => "pong"})
    Logger.debug("Sending heartbeat pong with payload: #{payload}")
    {:reply, {:text, payload}, state}
  end

  # Catch-all for any other info messages
  def handle_info(other, state) do
    Logger.debug("Unhandled info in ZKill.Websocket: #{inspect(other)}")
    {:ok, state}
  end

  @impl true
  def handle_frame({:text, raw_msg}, state) do
    Logger.debug("Received killstream frame: #{raw_msg}")

    case Jason.decode(raw_msg, keys: :strings) do
      {:ok, %{"killmail_id" => killmail_id} = data} ->
        zkb_info = Map.get(data, "zkb")
        Logger.info("[ZKill.Websocket] Received kill partial: killmail_id=#{killmail_id} zkb=#{inspect(zkb_info)}")
      {:ok, %{"kill_id" => kill_id} = data} ->
        sys_id = Map.get(data, "solar_system_id")
        Logger.info("[ZKill.Websocket] Received kill info: kill_id=#{kill_id}, system_id=#{sys_id} full message=#{inspect(data)}")
      {:ok, other_json} ->
        Logger.debug("Received unrecognized killstream JSON: #{inspect(other_json)}")
      {:error, decode_err} ->
        Logger.error("Error decoding zKill frame: #{inspect(decode_err)}. Raw: #{raw_msg}")
    end

    send(state.parent, {:zkill_message, raw_msg})
    {:ok, state}
  end

  @impl true
  def handle_ping({:ping, _data}, state) do
    Logger.debug("Received WS ping from zKill. Scheduling heartbeat pong in #{@heartbeat_interval}ms.")
    Process.send_after(self(), :heartbeat, @heartbeat_interval)
    {:ok, state}
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
  def handle_disconnect(%{code: code, reason: reason}, state) do
    Logger.warning("zKill websocket disconnected: code=#{inspect(code)}, reason=#{inspect(reason)}. Reconnecting...")
    {:reconnect, state}
  end

  # Fallback clause for disconnect messages that don't match the map pattern.
  def handle_disconnect(reason, state) do
    Logger.warning("zKill websocket disconnected (fallback): #{inspect(reason)}. Reconnecting...")
    {:reconnect, state}
  end

  @impl true
  def terminate(reason, _state) do
    Logger.warning("ZKill websocket terminating: #{inspect(reason)}")
    :ok
  end
end
