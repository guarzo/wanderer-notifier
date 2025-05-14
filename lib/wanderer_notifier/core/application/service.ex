# lib/wanderer_notifier/core/application/service.ex
defmodule WandererNotifier.Core.Application.Service do
  @moduledoc """
  Coordinates the websocket connection, kill processing, and periodic updates.
  """

  use GenServer

  alias WandererNotifier.Cache.CachexImpl, as: CacheRepo
  alias WandererNotifier.Config
  alias WandererNotifier.Killmail.Processor, as: KillmailProcessor
  alias WandererNotifier.Schedulers.{CharacterUpdateScheduler, SystemUpdateScheduler}
  alias WandererNotifier.Killmail.Websocket
  alias WandererNotifier.Logger.Logger, as: AppLogger

  @default_interval 30_000

  @typedoc "Internal state for the Service GenServer"
  @type state :: %__MODULE__.State{
          ws_pid: pid() | nil,
          service_start_time: integer()
        }

  defmodule State do
    @moduledoc false
    defstruct [
      :ws_pid,
      service_start_time: nil
    ]
  end

  ## Public API

  @doc "Start the service under its registered name"
  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @doc "Mark a kill ID as processed (for deduplication)"
  @spec mark_as_processed(integer() | String.t()) :: :ok
  def mark_as_processed(kill_id), do: GenServer.cast(__MODULE__, {:mark_as_processed, kill_id})

  @doc "Get the list of recent kills (for API)"
  defdelegate get_recent_kills(), to: KillmailProcessor

  ## GenServer callbacks

  @impl true
  def init(_opts) do
    AppLogger.startup_debug("Initializing WandererNotifier Service")
    Process.flag(:trap_exit, true)

    now = System.system_time(:second)
    KillmailProcessor.init()

    state =
      %State{service_start_time: now}
      |> connect_websocket()
      |> schedule_startup_notice()
      |> schedule_maintenance(@default_interval)
      |> schedule_websocket_health_check()

    # Schedule killmail stats logging
    KillmailProcessor.schedule_tasks()

    # Schedule the very first systems/characters update
    Process.send_after(self(), :update_tracked_data, 10_000)

    {:ok, state}
  end

  @impl true
  def handle_cast({:mark_as_processed, kill_id}, state) do
    ttl = Config.kill_dedup_ttl()

    case CacheRepo.set("kill:#{kill_id}", true, ttl) do
      :ok ->
        :ok

      {:error, reason} ->
        AppLogger.processor_warn("Failed to cache processed kill",
          id: kill_id,
          reason: inspect(reason)
        )
    end

    {:noreply, state}
  end

  @impl true
  def handle_info(:update_tracked_data, state) do
    SystemUpdateScheduler.run()
    CharacterUpdateScheduler.run()
    {:noreply, state}
  rescue
    e ->
      AppLogger.startup_error("Initial data update failed", error: Exception.message(e))
      Process.send_after(self(), :update_tracked_data, 5_000)
      {:noreply, state}
  end

  @impl true
  def handle_info(:send_startup_notification, state) do
    uptime = System.system_time(:second) - state.service_start_time
    AppLogger.startup_info("Service started", uptime: uptime)

    WandererNotifier.Notifiers.StatusNotifier.send_status_message(
      "WandererNotifier Service Status",
      "The service has started and is now operational."
    )

    {:noreply, state}
  rescue
    e ->
      AppLogger.startup_error("Startup notification failed", error: Exception.message(e))
      {:noreply, state}
  end

  @impl true
  def handle_info(:run_maintenance, state) do
    try do
      run_maintenance()
      # Log maintenance execution
      AppLogger.scheduler_info("System maintenance executed successfully")
    rescue
      e ->
        AppLogger.scheduler_error("Maintenance error", error: Exception.message(e))
    end

    # schedule next tick regardless of success/failure
    state = schedule_maintenance(state, @default_interval)
    {:noreply, state}
  end

  @impl true
  def handle_info({:zkill_message, raw_msg}, state) do
    # Save a backup of the current state in process dictionary
    # This helps recover if something goes wrong during processing
    Process.put(:backup_state, state)

    # Process the message but discard the result since it's not a state object
    # KillmailProcessor.process_zkill_message returns {:ok, kill_id | :skipped} | {:error, term()}
    case KillmailProcessor.process_zkill_message(raw_msg, state) do
      {:ok, _result} ->
        # Successfully processed
        {:noreply, state}

      {:error, reason} ->
        # Error occurred, log it but don't crash the process
        AppLogger.websocket_error("Error processing zkill message", error: inspect(reason))
        {:noreply, state}

      unexpected ->
        # Unexpected return value, log for debugging
        AppLogger.websocket_error("Unexpected return from process_zkill_message",
          return_value: inspect(unexpected)
        )

        {:noreply, state}
    end
  end

  @impl true
  # Handle Websocket DOWN messages uniformly
  def handle_info({:DOWN, _ref, :process, pid, reason}, %{ws_pid: pid} = state) do
    AppLogger.websocket_warn("Websocket DOWN (pid: #{inspect(pid)}); scheduling reconnect",
      reason: inspect(reason)
    )

    # Update Stats to show process crash
    WandererNotifier.Core.Stats.update_websocket(%{
      connected: false,
      connecting: true,
      last_disconnect: DateTime.utc_now()
    })

    # Use a shorter delay for faster recovery
    reconnect_delay = min(Config.websocket_reconnect_delay(), 5_000)
    AppLogger.websocket_info("Will attempt reconnect in #{reconnect_delay}ms")

    Process.send_after(self(), :reconnect_ws, reconnect_delay)
    {:noreply, %{state | ws_pid: nil}}
  end

  @impl true
  def handle_info(:reconnect_ws, state) do
    # Log the reconnection attempt
    AppLogger.websocket_info("Attempting to reconnect websocket")

    # Make sure we properly monitor the new connection
    new_state = connect_websocket(state)

    # If reconnection failed, schedule another attempt
    if new_state.ws_pid == nil do
      AppLogger.websocket_warn("Reconnection failed, scheduling another attempt")
      Process.send_after(self(), :reconnect_ws, Config.websocket_reconnect_delay())
    else
      AppLogger.websocket_info("Websocket reconnected successfully",
        pid: inspect(new_state.ws_pid)
      )
    end

    {:noreply, new_state}
  end

  @impl true
  def handle_info(:check_websocket_health, state) do
    # Ensure state is a proper State struct, if not recreate it to prevent crashes
    state = ensure_valid_state(state)

    # Schedule the next check
    state = schedule_websocket_health_check(state)

    # Get the current stats
    stats = WandererNotifier.Core.Stats.get_stats()
    ws_status = stats.websocket

    AppLogger.websocket_debug("Checking websocket health",
      connected: ws_status.connected,
      connecting: ws_status.connecting,
      ws_pid: if(state.ws_pid, do: inspect(state.ws_pid), else: "nil"),
      last_message:
        if(ws_status.last_message, do: DateTime.to_string(ws_status.last_message), else: "never"),
      reconnects: ws_status.reconnects
    )

    # Check if we need to force a reconnect
    if websocket_needs_reconnect?(state, ws_status) do
      # Send a reconnect message
      AppLogger.websocket_info("Health check initiating websocket reconnect")
      self() |> send(:reconnect_ws)
    end

    {:noreply, state}
  rescue
    e ->
      # If an error occurs during websocket health check, log it and ensure we have a valid state
      AppLogger.websocket_error("Error in websocket health check",
        error: Exception.message(e),
        state_type: inspect(state)
      )

      # Create a fresh state to avoid further errors
      fresh_state = %State{service_start_time: System.system_time(:second)}
      Process.send_after(self(), :reconnect_ws, 5_000)

      # Make sure we schedule another health check in the future
      schedule_websocket_health_check(fresh_state)

      {:noreply, fresh_state}
  end

  @impl true
  def handle_info({:websocket_terminated, pid, reason}, %{ws_pid: current_pid} = state) do
    # Only handle if this is our current websocket
    if pid == current_pid do
      AppLogger.websocket_info("Received websocket termination notification",
        pid: inspect(pid),
        reason: inspect(reason)
      )

      # Mark the process as nil
      new_state = %{state | ws_pid: nil}

      # Schedule reconnection
      reconnect_delay = min(Config.websocket_reconnect_delay(), 3_000)
      Process.send_after(self(), :reconnect_ws, reconnect_delay)

      {:noreply, new_state}
    else
      # This is a termination for an old websocket we don't care about
      AppLogger.websocket_debug("Ignoring termination for old websocket",
        terminated_pid: inspect(pid),
        current_pid: inspect(current_pid)
      )

      {:noreply, state}
    end
  end

  @impl true
  # Catch-all to make unhandled messages visible in logs
  def handle_info(other, state) do
    AppLogger.processor_debug("Unhandled message in Service", msg: inspect(other))
    {:noreply, state}
  end

  ## Internal helpers

  defp check_pid_and_connect(pid, state) do
    if Process.alive?(pid) do
      state
    else
      # PID exists but process is dead, clear it and reconnect
      AppLogger.websocket_debug("Websocket PID exists but process is dead", pid: inspect(pid))
      connect_websocket(%{state | ws_pid: nil})
    end
  end

  # (Re)establish the Killmail Websocket, if enabled
  defp connect_websocket(%State{ws_pid: pid} = state) when is_pid(pid),
    do: check_pid_and_connect(pid, state)

  defp connect_websocket(state) do
    if Config.websocket_enabled?() do
      AppLogger.websocket_debug("Starting Killmail Websocket")

      # Clear any previous connection state
      if state.ws_pid != nil do
        AppLogger.websocket_debug("Clearing previous websocket PID",
          old_pid: inspect(state.ws_pid)
        )
      end

      # Ensure we have current Stats
      WandererNotifier.Core.Stats.update_websocket(%{connecting: true})

      # Give a short delay before connection attempt (helps with rapid reconnection)
      Process.sleep(100)

      try do
        case Websocket.start_link(self()) do
          {:ok, ws_pid} ->
            # Monitor the process so we get notified if it crashes
            monitor_ref = Process.monitor(ws_pid)

            AppLogger.websocket_info("Successfully started websocket",
              pid: inspect(ws_pid),
              monitor_ref: inspect(monitor_ref)
            )

            %{state | ws_pid: ws_pid}

          {:error, reason} ->
            AppLogger.websocket_error("Websocket start failed", error: inspect(reason))
            # Use a shorter delay for faster retry
            reconnect_delay = min(Config.websocket_reconnect_delay(), 5_000)
            Process.send_after(self(), :reconnect_ws, reconnect_delay)
            state
        end
      rescue
        e ->
          AppLogger.websocket_error("Exception starting websocket",
            error: Exception.message(e),
            stacktrace: Exception.format_stacktrace(__STACKTRACE__)
          )

          Process.send_after(self(), :reconnect_ws, Config.websocket_reconnect_delay())
          state
      end
    else
      AppLogger.websocket_info("Websocket disabled by configuration")
      state
    end
  end

  # Schedule the startup notification
  defp schedule_startup_notice(state) do
    Process.send_after(self(), :send_startup_notification, 2_000)
    state
  end

  # Schedule the maintenance loop
  @spec schedule_maintenance(state(), non_neg_integer()) :: state()
  defp schedule_maintenance(state, interval) do
    Process.send_after(self(), :run_maintenance, interval)
    state
  end

  # Schedule a periodic websocket health check
  defp schedule_websocket_health_check(state) do
    # Check every 10 seconds
    Process.send_after(self(), :check_websocket_health, 10_000)
    state
  end

  # What runs on each maintenance tick
  defp run_maintenance do
    SystemUpdateScheduler.run()
    CharacterUpdateScheduler.run()
    KillmailProcessor.schedule_tasks()
    :ok
  end

  # Helper to ensure we have a valid State struct
  defp ensure_valid_state(state) do
    cond do
      # Valid State struct with ws_pid field
      is_map(state) and is_map_key(state, :ws_pid) and is_map_key(state, :service_start_time) ->
        state

      # Process dictionary has state backup
      Process.get(:backup_state) ->
        AppLogger.websocket_info("Restored state from backup")
        Process.get(:backup_state)

      # Create new state as fallback
      true ->
        AppLogger.websocket_warn("Created new State struct due to invalid state",
          received: inspect(state)
        )

        %State{service_start_time: System.system_time(:second)}
    end
  end

  # Helper function to determine if websocket needs reconnection
  defp websocket_needs_reconnect?(state, ws_status) do
    cond do
      # No process ID for websocket
      state.ws_pid == nil ->
        AppLogger.websocket_warn("Health check found nil websocket PID")
        true

      # PID exists but process is dead
      not Process.alive?(state.ws_pid) ->
        AppLogger.websocket_warn("Health check found dead websocket process",
          pid: inspect(state.ws_pid)
        )

        true

      # Everything looks connected in stats
      ws_status.connected ->
        false

      # We're already in connecting state
      ws_status.connecting ->
        stalled_reconnect?(ws_status.last_disconnect)

      # Not connected or connecting - force reconnect
      true ->
        AppLogger.websocket_warn("Health check found disconnected websocket")
        true
    end
  end

  # Helper to determine if a reconnect attempt has stalled
  defp stalled_reconnect?(nil), do: false

  defp stalled_reconnect?(timestamp) do
    diff = DateTime.diff(DateTime.utc_now(), timestamp, :second)

    if diff > 30 do
      AppLogger.websocket_warn("Health check found stalled reconnect",
        seconds_since_disconnect: diff
      )

      true
    else
      false
    end
  end
end
