defmodule WandererNotifier.Service do
  @moduledoc """
  The main WandererNotifier service (GenServer).
  Coordinates periodic maintenance and kill processing.
  """
  use GenServer
  require Logger

  alias WandererNotifier.Discord.Notifier
  alias WandererNotifier.ZKill.Websocket, as: ZKillWebsocket
  alias WandererNotifier.Service.Maintenance
  alias WandererNotifier.Service.KillProcessor

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

  @impl true
  def init(_opts) do
    Logger.info("Initializing WandererNotifier Service...")
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
    Notifier.send_message("WandererNotifier Service started. Listening for kill notifications.")
    schedule_maintenance()
    {:ok, state}
  end

  def mark_as_processed(kill_id) do
    GenServer.cast(__MODULE__, {:mark_as_processed, kill_id})
  end

  @impl true
  def handle_cast({:mark_as_processed, kill_id}, state) do
    if Map.has_key?(state.processed_kill_ids, kill_id) do
      {:noreply, state}
    else
      new_state =
        %{
          state
          | processed_kill_ids:
              Map.put(state.processed_kill_ids, kill_id, :os.system_time(:second))
        }

      {:noreply, new_state}
    end
  end

  @impl true
  def handle_info(:maintenance, state) do
    Logger.debug("Running periodic maintenance checks")
    new_state = Maintenance.do_periodic_checks(state)
    schedule_maintenance()
    {:noreply, new_state}
  end

  @impl true
  def handle_info({:zkill_message, message}, state) do
    Logger.debug("Received zkill message: #{message}")
    new_state = KillProcessor.process_zkill_message(message, state)
    {:noreply, new_state}
  end

  @impl true
  def handle_info(:ws_disconnected, state) do
    Logger.warning("Websocket disconnected, scheduling reconnect in #{@reconnect_delay_ms}ms")
    Process.send_after(self(), :reconnect_ws, @reconnect_delay_ms)
    {:noreply, state}
  end

  @impl true
  def handle_info(:reconnect_ws, state) do
    Logger.info("Attempting to reconnect zKill websocket...")
    new_state = reconnect_zkill_ws(state)
    {:noreply, new_state}
  end

  # Distinguish normal vs. abnormal exits
  @impl true
  def handle_info({:EXIT, pid, reason}, state) when reason == :normal do
    Logger.debug("Linked process #{inspect(pid)} exited normally.")
    {:noreply, state}
  end

  @impl true
  def handle_info({:EXIT, pid, reason}, state) do
    Logger.error("Linked process #{inspect(pid)} exited with reason: #{inspect(reason)}")

    # Check if the crashed process is the ZKill websocket
    if pid == state.ws_pid do
      Logger.warning("ZKill websocket crashed. Scheduling reconnect in #{@reconnect_delay_ms}ms")
      Process.send_after(self(), :reconnect_ws, @reconnect_delay_ms)
      {:noreply, %{state | ws_pid: nil}}
    else
      {:noreply, state}
    end
  end

  @impl true
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
