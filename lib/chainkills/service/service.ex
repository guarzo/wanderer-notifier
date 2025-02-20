defmodule ChainKills.Service do
  @moduledoc """
  The main ChainKills service (GenServer).
  Coordinates periodic maintenance and kill processing.
  """
  use GenServer
  require Logger

  alias ChainKills.Discord.Notifier
  alias ChainKills.ZKill.Websocket, as: ZKillWebsocket
  alias ChainKills.Service.Maintenance
  alias ChainKills.Service.KillProcessor

  @zkill_ws_url "wss://zkillboard.com/websocket/"
  @reconnect_delay_ms 10_000
  @maintenance_interval_ms 60_000

  defmodule State do
    @moduledoc """
    Maintains the state of the application.
    """
    defstruct [
      :ws_pid,
      processed_kill_ids: %{},
      last_status_time: nil,
      service_start_time: nil,
      last_systems_update: nil,
      last_backup_check: nil,
      last_characters_update: nil
    ]
  end

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def stop do
    GenServer.stop(__MODULE__)
  end

  def init(_opts) do
    Logger.info("Initializing ChainKills Service...")
    # Trap exits so the GenServer doesn't crash when a linked process dies
    Process.flag(:trap_exit, true)
    now = :os.system_time(:second)

    state = %State{
      service_start_time: now,
      last_status_time: now,
      last_systems_update: now,
      last_backup_check: now
    }

    state = start_zkill_ws(state)
    # Send one startup notification to Discord.
    Notifier.send_message("ChainKills Service started. Listening for kill notifications.")
    schedule_maintenance()
    {:ok, state}
  end

  def handle_info(:maintenance, state) do
    Logger.debug("Running periodic maintenance checks")
    new_state = Maintenance.do_periodic_checks(state)
    schedule_maintenance()
    {:noreply, new_state}
  end

  def handle_info({:zkill_message, message}, state) do
    Logger.debug("Received zkill message: #{message}")
    new_state = KillProcessor.process_zkill_message(message, state)
    {:noreply, new_state}
  end

  def handle_info(:ws_disconnected, state) do
    Logger.warning("Websocket disconnected, scheduling reconnect in #{@reconnect_delay_ms}ms")
    Notifier.send_message("Websocket disconnected, reconnecting in #{@reconnect_delay_ms}ms")
    Process.send_after(self(), :reconnect_ws, @reconnect_delay_ms)
    {:noreply, state}
  end

  def handle_info(:reconnect_ws, state) do
    Logger.info("Attempting to reconnect zKill websocket...")
    new_state = reconnect_zkill_ws(state)
    {:noreply, new_state}
  end

  # Updated to differentiate between normal and abnormal exits.
  def handle_info({:EXIT, _pid, reason}, state) when reason == :normal do
    Logger.info("Linked process exited normally.")
    {:noreply, state}
  end

  def handle_info({:EXIT, _pid, reason}, state) do
    Logger.error("Linked process exited with reason: #{inspect(reason)}")
    {:noreply, state}
  end

  def terminate(_reason, state) do
    if state.ws_pid, do: Process.exit(state.ws_pid, :normal)
    Notifier.close()
    :ok
  end

  defp schedule_maintenance do
    Process.send_after(self(), :maintenance, @maintenance_interval_ms)
  end

  defp start_zkill_ws(state) do
    case ZKillWebsocket.start_link(self(), @zkill_ws_url) do
      {:ok, pid} ->
        Logger.info("ZKill websocket started: #{inspect(pid)}")
        %{state | ws_pid: pid}
      {:error, reason} ->
        Logger.error("Failed to start websocket: #{inspect(reason)}")
        Notifier.send_message("Failed to start websocket: #{inspect(reason)}")
        state
    end
  end

  defp reconnect_zkill_ws(state) do
    case ZKillWebsocket.start_link(self(), @zkill_ws_url) do
      {:ok, pid} ->
        Logger.info("Reconnected to zKill websocket: #{inspect(pid)}")
        %{state | ws_pid: pid}
      {:error, reason} ->
        Logger.error("Reconnection failed: #{inspect(reason)}")
        Process.send_after(self(), :reconnect_ws, @reconnect_delay_ms)
        state
    end
  end
end
