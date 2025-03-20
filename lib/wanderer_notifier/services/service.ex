defmodule WandererNotifier.Services.Service do
  @moduledoc """
  The main WandererNotifier service (GenServer).
  Coordinates periodic maintenance and kill processing.
  """
  use GenServer
  require Logger

  alias WandererNotifier.Api.ZKill.Websocket, as: ZKillWebsocket
  alias WandererNotifier.Core.Config.Timings
  alias WandererNotifier.Notifiers.Factory, as: NotifierFactory
  alias WandererNotifier.Services.Maintenance.Scheduler, as: MaintenanceScheduler

  @zkill_ws_url "wss://zkillboard.com/websocket/"

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
      last_characters_update: nil,
      systems_count: 0,
      characters_count: 0
    ]
  end

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: WandererNotifier.Service)
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
      last_characters_update: now
    }

    state = start_zkill_ws(state)
    # Send one startup notification to Discord.
    WandererNotifier.Notifiers.Factory.notify(:send_message, [
      "WandererNotifier Service started. Listening for notifications."
    ])

    # Run initial maintenance tasks immediately
    Logger.info("Running initial maintenance tasks at startup...")
    # Run after 5 seconds to allow system to initialize
    Process.send_after(self(), :initial_maintenance, 5000)

    # Schedule regular maintenance
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
    # Schedule the next maintenance check
    schedule_maintenance()

    # Run maintenance checks using the aliased module
    new_state = MaintenanceScheduler.tick(state)

    {:noreply, new_state}
  end

  @impl true
  def handle_info(:initial_maintenance, state) do
    Logger.info("Running initial maintenance tasks...")

    # Add error handling around maintenance tasks
    new_state =
      try do
        # Force a full update of all systems and characters using the aliased module
        MaintenanceScheduler.do_initial_checks(state)
      rescue
        e ->
          Logger.error("Error during initial maintenance: #{inspect(e)}")
          Logger.error("Stacktrace: #{inspect(Process.info(self(), :current_stacktrace))}")
          # Return the original state if maintenance fails
          state
      end

    Logger.info("Initial maintenance tasks completed")
    {:noreply, new_state}
  end

  @impl true
  def handle_info({:zkill_message, message}, state) do
    Logger.info("SERVICE TRACE: Received zkill message from WebSocket, length: #{String.length(message)}")
    # Process the message with the KillProcessor
    new_state = WandererNotifier.Services.KillProcessor.process_zkill_message(message, state)
    {:noreply, new_state}
  end

  @impl true
  def handle_info(:ws_disconnected, state) do
    Logger.warning(
      "Websocket disconnected, scheduling reconnect in #{Timings.reconnect_delay()}ms"
    )

    Process.send_after(self(), :reconnect_ws, Timings.reconnect_delay())
    {:noreply, state}
  end

  @impl true
  def handle_info(:reconnect_ws, state) do
    Logger.info("Attempting to reconnect zKill websocket...")
    new_state = reconnect_zkill_ws(state)
    {:noreply, new_state}
  end

  @impl true
  def handle_info(:force_refresh_cache, state) do
    Logger.warning(
      "Received force_refresh_cache message. Refreshing critical data after cache recovery..."
    )

    # Run maintenance tasks to repopulate the cache using the aliased module
    new_state = MaintenanceScheduler.do_initial_checks(state)

    Logger.info("Cache refresh completed after recovery")
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
    Logger.warning("Linked process #{inspect(pid)} exited with reason: #{inspect(reason)}")

    # Check if the crashed process is the ZKill websocket
    if pid == state.ws_pid do
      Logger.warning(
        "ZKill websocket crashed. Scheduling reconnect in #{Timings.reconnect_delay()}ms"
      )

      Process.send_after(self(), :reconnect_ws, Timings.reconnect_delay())
      {:noreply, %{state | ws_pid: nil}}
    else
      {:noreply, state}
    end
  end

  @impl true
  def terminate(_reason, state) do
    if state.ws_pid, do: Process.exit(state.ws_pid, :normal)
    :ok
  end

  defp schedule_maintenance do
    Process.send_after(self(), :maintenance, Timings.maintenance_interval())
  end

  defp start_zkill_ws(state) do
    case ZKillWebsocket.start_link(self(), @zkill_ws_url) do
      {:ok, pid} ->
        Logger.info("ZKill websocket started: #{inspect(pid)}")
        %{state | ws_pid: pid}

      {:error, reason} ->
        Logger.error("Failed to start websocket: #{inspect(reason)}")
        NotifierFactory.notify(:send_message, ["Failed to start websocket: #{inspect(reason)}"])
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
        Process.send_after(self(), :reconnect_ws, Timings.reconnect_delay())
        state
    end
  end
end
