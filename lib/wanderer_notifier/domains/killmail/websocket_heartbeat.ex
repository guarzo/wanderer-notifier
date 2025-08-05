defmodule WandererNotifier.Domains.Killmail.WebSocketHeartbeat do
  @moduledoc """
  Manages WebSocket heartbeat logic for Phoenix channels.

  Handles heartbeat scheduling, message creation, and connection uptime tracking
  for WebSocket connections to Phoenix-based servers.
  """

  require Logger

  @default_heartbeat_interval 30_000

  # ══════════════════════════════════════════════════════════════════════════════
  # Public API
  # ══════════════════════════════════════════════════════════════════════════════

  @doc """
  Schedules the next heartbeat message.

  ## Parameters
  - interval_ms: Heartbeat interval in milliseconds (default: 30 seconds)

  ## Returns
  Timer reference for the scheduled heartbeat.
  """
  def schedule_heartbeat(interval_ms \\ @default_heartbeat_interval) do
    Process.send_after(self(), :heartbeat, interval_ms)
  end

  @doc """
  Creates a Phoenix channel heartbeat message.

  ## Returns
  Map containing the heartbeat message structure for Phoenix channels.
  """
  def create_heartbeat_message do
    %{
      topic: "phoenix",
      event: "heartbeat",
      payload: %{},
      ref: "heartbeat_#{System.system_time(:millisecond)}"
    }
  end

  @doc """
  Handles a heartbeat event and returns the appropriate WebSocket response.

  ## Parameters
  - state: Current WebSocket state containing connection information
  - interval_ms: Optional custom heartbeat interval

  ## Returns
  WebSocket response tuple with next scheduled heartbeat in updated state.
  """
  def handle_heartbeat(state, interval_ms \\ @default_heartbeat_interval) do
    log_heartbeat_uptime(state)
    record_heartbeat_in_monitoring(state)
    send_heartbeat_message(state, interval_ms)
  end

  @doc """
  Handles a pong response from the server.

  ## Parameters
  - state: Current WebSocket state

  ## Returns
  Updated state with pong timestamp recorded.
  """
  def handle_pong(state) do
    Logger.debug("Received pong from server")
    %{state | last_pong_at: DateTime.utc_now()}
  end

  @doc """
  Gets the connection uptime in seconds.

  ## Parameters
  - state: WebSocket state containing connected_at timestamp

  ## Returns
  Integer representing uptime in seconds, or 0 if not connected.
  """
  def get_uptime_seconds(state) do
    case state.connected_at do
      nil -> 0
      connected_at -> DateTime.diff(DateTime.utc_now(), connected_at, :second)
    end
  end

  @doc """
  Cancels an existing heartbeat timer.

  ## Parameters
  - timer_ref: Timer reference to cancel (can be nil)

  ## Returns
  :ok
  """
  def cancel_heartbeat(nil), do: :ok

  def cancel_heartbeat(timer_ref) when is_reference(timer_ref) do
    Process.cancel_timer(timer_ref)
    :ok
  end

  # ══════════════════════════════════════════════════════════════════════════════
  # Private Helper Functions
  # ══════════════════════════════════════════════════════════════════════════════

  defp log_heartbeat_uptime(state) do
    case state.connected_at do
      nil ->
        Logger.debug("WebSocket heartbeat - No connection time recorded")

      connected_at ->
        uptime = DateTime.diff(DateTime.utc_now(), connected_at, :second)

        Logger.debug(
          "WebSocket heartbeat - Connection uptime: #{uptime}s (#{div(uptime, 60)}m #{rem(uptime, 60)}s)"
        )
    end
  end

  defp record_heartbeat_in_monitoring(_state) do
    # Heartbeat recording removed - ConnectionHealthService doesn't need explicit heartbeats
    # Connection health is now tracked by simple process alive checks
    :ok
  end

  defp send_heartbeat_message(state, interval_ms) do
    if state.channel_ref do
      send_heartbeat_with_encoding(state, interval_ms)
    else
      # No channel joined yet, just schedule next heartbeat
      {:ok, schedule_next_heartbeat(state, interval_ms)}
    end
  end

  defp send_heartbeat_with_encoding(state, interval_ms) do
    heartbeat_message = create_heartbeat_message()

    case Jason.encode(heartbeat_message) do
      {:ok, json} ->
        {:reply, {:text, json}, schedule_next_heartbeat(state, interval_ms)}

      {:error, _reason} ->
        {:ok, schedule_next_heartbeat(state, interval_ms)}
    end
  end

  defp schedule_next_heartbeat(state, interval_ms) do
    %{state | heartbeat_ref: schedule_heartbeat(interval_ms)}
  end
end
