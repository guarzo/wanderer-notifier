# lib/wanderer_notifier/core/application/service.ex
defmodule WandererNotifier.Core.Application.Service do
  @moduledoc """
  Coordinates the websocket connection, kill processing, and periodic updates.
  """

  use GenServer

  alias WandererNotifier.Cache.CachexImpl,          as: CacheRepo
  alias WandererNotifier.Config
  alias WandererNotifier.Killmail.Processor,        as: KillmailProcessor
  alias WandererNotifier.Schedulers.{CharacterUpdateScheduler, SystemUpdateScheduler}
  alias WandererNotifier.Killmail.Websocket
  alias WandererNotifier.Logger.Logger,             as: AppLogger

  @default_interval :timer.minutes(5)

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

  @doc "Send a test kill notification (for API)"
  defdelegate send_test_kill_notification(), to: KillmailProcessor

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

    {:ok, state}
  end

  @impl true
  def handle_cast({:mark_as_processed, kill_id}, state) do
    ttl = Config.kill_dedup_ttl()
    case CacheRepo.set("kill:#{kill_id}", true, ttl) do
      :ok -> :ok
      {:error, reason} ->
        AppLogger.processor_warn("Failed to cache processed kill", id: kill_id, reason: inspect(reason))
    end

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
    run_maintenance()

    # schedule next tick
    state = schedule_maintenance(state, @default_interval)
    {:noreply, state}
  rescue
    e ->
      AppLogger.scheduler_error("Maintenance error", error: Exception.message(e))
      state = schedule_maintenance(state, @default_interval)
      {:noreply, state}
  end

  @impl true
  def handle_info({:zkill_message, raw_msg}, state) do
    new_state = KillmailProcessor.process_zkill_message(raw_msg, state)
    {:noreply, new_state}
  end

  @impl true
  # Handle Websocket DOWN messages uniformly
  def handle_info({:DOWN, _ref, :process, pid, reason}, %{ws_pid: pid} = state) do
    AppLogger.websocket_warn("Websocket down; scheduling reconnect", reason: inspect(reason))
    Process.send_after(self(), :reconnect_ws, Config.websocket_reconnect_delay())
    {:noreply, %{state | ws_pid: nil}}
  end

  @impl true
  def handle_info(:reconnect_ws, state) do
    {:noreply, connect_websocket(state)}
  end

  @impl true
  # Catch-all to make unhandled messages visible in logs
  def handle_info(other, state) do
    AppLogger.processor_debug("Unhandled message in Service", msg: inspect(other))
    {:noreply, state}
  end

  ## Internal helpers

  # (Re)establish the Killmail Websocket, if enabled
  defp connect_websocket(%State{ws_pid: pid} = state) when is_pid(pid), do: state
  defp connect_websocket(state) do
    if Config.websocket_enabled?() do
      AppLogger.websocket_debug("Starting Killmail Websocket")
      case Websocket.start_link(self()) do
        {:ok, ws_pid} ->
          Process.monitor(ws_pid)
          %{state | ws_pid: ws_pid}

        {:error, reason} ->
          AppLogger.websocket_error("Websocket start failed", error: inspect(reason))
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

  # What runs on each maintenance tick
  defp run_maintenance do
    SystemUpdateScheduler.run()
    CharacterUpdateScheduler.run()
    KillmailProcessor.schedule_tasks()
    :ok
  end
end
