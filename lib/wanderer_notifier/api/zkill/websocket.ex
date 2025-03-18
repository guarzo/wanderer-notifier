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

  def start_link(parent, url) do
    WebSockex.start_link(url, __MODULE__, %{parent: parent, connected: false})
  end

  def init(state) do
    Logger.info("Initializing zKill websocket client.")
    {:ok, state}
  end

  @impl true
  def handle_connect(_conn, state) do
    try do
      Logger.info("Connected to zKill websocket.")
      new_state = Map.put(state, :connected, true)

      # Update websocket status
      try do
        WandererNotifier.Stats.update_websocket(%{
          connected: true,
          last_message: DateTime.utc_now(),
          reconnects: Map.get(state, :reconnects, 0)
        })
      rescue
        _ -> :ok
      end

      # Schedule subscription so that send_frame is not called within handle_connect
      Process.send_after(self(), :subscribe, 0)
      {:ok, new_state}
    rescue
      e ->
        Logger.error("Error in handle_connect: #{inspect(e)}")
        {:ok, state}
    end
  end

  @impl true
  def handle_info(:subscribe, state) do
    try do
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
    rescue
      e ->
        Logger.error("Error in handle_info(:subscribe): #{inspect(e)}")
        {:ok, state}
    end
  end

  def handle_info(:heartbeat, state) do
    try do
      payload = Jason.encode!(%{"action" => "pong"})
      Logger.debug("Sending heartbeat pong with payload: #{payload}")
      {:reply, {:text, payload}, state}
    rescue
      e ->
        Logger.error("Error in handle_info(:heartbeat): #{inspect(e)}")
        {:ok, state}
    end
  end

  # Catch-all for any other info messages
  def handle_info(other, state) do
    try do
      Logger.debug("Unhandled info in ZKill.Websocket: #{inspect(other)}")
      {:ok, state}
    rescue
      e ->
        Logger.error("Error in handle_info/2: #{inspect(e)}")
        {:ok, state}
    end
  end

  @impl true
  def handle_frame({:text, raw_msg}, state) do
    try do
      Logger.debug("Received killstream frame: #{raw_msg}")

      try do
        case Jason.decode(raw_msg, keys: :strings) do
          {:ok, %{"killmail_id" => killmail_id} = data} when is_map_key(data, "zkb") ->
            zkb_info = Map.get(data, "zkb")

            # Truncate zkb info for logging
            truncated_zkb = truncate_zkb_for_logging(zkb_info)

            Logger.debug(
              "[ZKill.Websocket] Received kill partial: killmail_id=#{killmail_id} zkb=#{truncated_zkb}"
            )

            # Process the kill message directly using KillProcessor
            if Map.has_key?(state, :parent) and is_pid(state.parent) and Process.alive?(state.parent) do
              # Forward the message to the parent process for processing
              send(state.parent, {:zkill_message, raw_msg})
              Logger.debug("Forwarded kill message with ID #{killmail_id} to parent process for processing")
            else
              # If parent process is not available, process directly
              Logger.warning("Parent process not available, processing kill directly")
              KillProcessor.process_zkill_message(data, %{})
            end

          {:ok, %{"kill_id" => kill_id} = data} ->
            sys_id = Map.get(data, "solar_system_id")

            Logger.debug(
              "[ZKill.Websocket] Received kill info: kill_id=#{kill_id}, system_id=#{sys_id} full message=#{inspect(data)}"
            )

            # Forward the message to the parent process
            if Map.has_key?(state, :parent) and is_pid(state.parent) and Process.alive?(state.parent) do
              send(state.parent, {:zkill_message, raw_msg})
              Logger.debug("Forwarded kill message with ID #{kill_id} to parent process for processing")
            end

          {:ok, %{"killmail_id" => _} = data} ->
            # Handle case where killmail_id exists but zkb doesn't
            Logger.debug("Received killmail without zkb data: #{inspect(data)}")

            # Forward the message to the parent process
            if Map.has_key?(state, :parent) and is_pid(state.parent) and Process.alive?(state.parent) do
              send(state.parent, {:zkill_message, raw_msg})
            end

          {:ok, %{"action" => action} = data} ->
            # Handle action messages like pings, etc.
            Logger.debug("Received action message: #{action}, data: #{inspect(data)}")

          {:ok, other_json} ->
            Logger.debug("Received unrecognized killstream JSON: #{inspect(other_json)}")

            # Forward the message to the parent process just in case
            if Map.has_key?(state, :parent) and is_pid(state.parent) and Process.alive?(state.parent) do
              send(state.parent, {:zkill_message, raw_msg})
            end

          {:error, decode_err} ->
            Logger.error("Error decoding zKill frame: #{inspect(decode_err)}. Raw: #{raw_msg}")
        end
      rescue
        e ->
          Logger.error("Error processing zKill frame: #{inspect(e)}. Raw: #{raw_msg}")
      catch
        kind, reason ->
          Logger.error("Caught #{kind} while processing zKill frame: #{inspect(reason)}. Raw: #{raw_msg}")
      end

      {:ok, state}
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

  # Handle binary frames
  def handle_frame({:binary, data}, state) do
    try do
      Logger.debug("Received binary frame from zKill (#{byte_size(data)} bytes)")
      {:ok, state}
    rescue
      e ->
        Logger.error("Error in handle_frame/2 (binary): #{inspect(e)}")
        {:ok, state}
    catch
      kind, reason ->
        Logger.error("Caught #{kind} in handle_frame/2 (binary): #{inspect(reason)}")
        {:ok, state}
    end
  end

  @impl true
  def handle_frame({:ping, ping_frame}, state) do
    if ping_frame == "ping" do
      Logger.debug(
        "Received WS ping from zKill. Scheduling heartbeat pong in #{Timings.websocket_heartbeat_interval()}ms."
      )

      Process.send_after(self(), :heartbeat, Timings.websocket_heartbeat_interval())
      {:ok, state}
    else
      Logger.warning(
        "Received unexpected ping format from zKill: #{inspect(ping_frame)}. Scheduling heartbeat pong in #{Timings.websocket_heartbeat_interval()}ms."
      )

      Process.send_after(self(), :heartbeat, Timings.websocket_heartbeat_interval())
      {:ok, state}
    end
  end

  # Catch-all for any other frame types
  def handle_frame(frame, state) do
    try do
      Logger.debug("Received unexpected frame type from zKill: #{inspect(frame)}")
      {:ok, state}
    rescue
      e ->
        Logger.error("Error in handle_frame/2 (other): #{inspect(e)}")
        {:ok, state}
    catch
      kind, reason ->
        Logger.error("Caught #{kind} in handle_frame/2: #{inspect(reason)}")
        {:ok, state}
    end
  end

  @impl true
  def handle_pong({:pong, data}, state) do
    try do
      Logger.debug("Received WS pong from zKill: #{inspect(data)}")
      {:ok, state}
    rescue
      e ->
        Logger.error("Error in handle_pong/2: #{inspect(e)}")
        {:ok, state}
    catch
      kind, reason ->
        Logger.error("Caught #{kind} in handle_pong/2: #{inspect(reason)}")
        {:ok, state}
    end
  end

  @impl true
  def handle_cast(msg, state) do
    try do
      Logger.debug("Unhandled cast in ZKill.Websocket: #{inspect(msg)}")
      {:ok, state}
    rescue
      e ->
        Logger.error("Error in handle_cast/2: #{inspect(e)}")
        {:ok, state}
    end
  end

  @impl true
  def handle_disconnect(%{code: code, reason: reason}, state) do
    try do
      Logger.warning(
        "zKill websocket disconnected: code=#{inspect(code)}, reason=#{inspect(reason)}. Reconnecting..."
      )

      # Update websocket status
      reconnects = Map.get(state, :reconnects, 0) + 1
      new_state = Map.put(state, :reconnects, reconnects)

      try do
        WandererNotifier.Stats.update_websocket(%{
          connected: false,
          last_message: DateTime.utc_now(),
          reconnects: reconnects
        })
      rescue
        _ -> :ok
      end

      {:reconnect, new_state}
    rescue
      e ->
        Logger.error("Error in handle_disconnect/2: #{inspect(e)}")
        {:reconnect, state}
    catch
      kind, reason_caught ->
        Logger.error("Caught #{kind} in handle_disconnect/2: #{inspect(reason_caught)}")
        {:reconnect, state}
    end
  end

  # Fallback clause for disconnect messages that don't match the map pattern.
  def handle_disconnect(reason, state) do
    try do
      Logger.warning("zKill websocket disconnected (fallback): #{inspect(reason)}. Reconnecting...")

      # Update websocket status
      reconnects = Map.get(state, :reconnects, 0) + 1
      new_state = Map.put(state, :reconnects, reconnects)

      try do
        WandererNotifier.Stats.update_websocket(%{
          connected: false,
          last_message: DateTime.utc_now(),
          reconnects: reconnects
        })
      rescue
        _ -> :ok
      end

      {:reconnect, new_state}
    rescue
      e ->
        Logger.error("Error in handle_disconnect/2 (fallback): #{inspect(e)}")
        {:reconnect, state}
    catch
      kind, reason_caught ->
        Logger.error("Caught #{kind} in handle_disconnect/2 (fallback): #{inspect(reason_caught)}")
        {:reconnect, state}
    end
  end

  @impl true
  def terminate(reason, _state) do
    try do
      Logger.warning("ZKill websocket terminating: #{inspect(reason)}")
      :ok
    rescue
      e ->
        Logger.error("Error in terminate/2: #{inspect(e)}")
        :ok
    catch
      kind, reason_caught ->
        Logger.error("Caught #{kind} in terminate/2: #{inspect(reason_caught)}")
        :ok
    end
  end

  # Helper function to truncate zkb info for logging
  defp truncate_zkb_for_logging(%{"zkb" => zkb} = _message) when is_map(zkb) do
    # Extract only essential information
    essential_keys = ["totalValue", "url", "locationID"]
    truncated_map = Map.take(zkb, essential_keys)

    # Add a note about truncated fields
    truncated_count = map_size(zkb) - map_size(truncated_map)
    result = if truncated_count > 0 do
      Map.put(truncated_map, "_truncated", "#{truncated_count} fields omitted")
    else
      truncated_map
    end

    inspect(result, limit: 5)
  end

  defp truncate_zkb_for_logging(other), do: inspect(other, limit: 5)
end
