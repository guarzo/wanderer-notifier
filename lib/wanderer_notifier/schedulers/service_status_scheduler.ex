defmodule WandererNotifier.Schedulers.ServiceStatusScheduler do
  @moduledoc """
  Scheduler responsible for generating periodic service status reports.
  """
  use GenServer
  alias WandererNotifier.Shared.Logger.Logger, as: AppLogger
  alias WandererNotifier.Shared.Types.Constants
  alias WandererNotifier.Shared.Utils.TimeUtils

  @behaviour WandererNotifier.Schedulers.Scheduler

  defmodule State do
    @moduledoc """
    State for the service status scheduler.
    """
    defstruct last_run: nil,
              run_count: 0,
              timer_ref: nil

    @type t :: %__MODULE__{
            last_run: DateTime.t() | nil,
            run_count: non_neg_integer(),
            timer_ref: reference() | nil
          }

    @spec new() :: t()
    def new, do: %__MODULE__{}
  end

  @impl true
  def config, do: %{type: :interval, spec: Constants.service_status_interval()}

  @impl true
  def run do
    generate_service_status_report()
    :ok
  end

  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      type: :worker,
      restart: :permanent,
      shutdown: 500
    }
  end

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl GenServer
  def init(opts) do
    AppLogger.scheduler_info("ServiceStatusScheduler starting", opts: opts)
    state = State.new()
    timer_ref = schedule_next_run()
    {:ok, %{state | timer_ref: timer_ref}}
  end

  @impl GenServer
  def handle_info(:run_status_report, state) do
    try do
      run()
    rescue
      e ->
        AppLogger.scheduler_error("Error in scheduled status report",
          error: Exception.message(e)
        )
    end

    timer_ref = schedule_next_run()

    new_state = %{
      state
      | last_run: TimeUtils.now(),
        run_count: state.run_count + 1,
        timer_ref: timer_ref
    }

    {:noreply, new_state}
  end

  @impl GenServer
  def handle_info(_msg, state) do
    {:noreply, state}
  end

  defp schedule_next_run do
    %{spec: interval} = config()
    Process.send_after(self(), :run_status_report, interval)
  end

  defp generate_service_status_report do
    alias WandererNotifier.Domains.Notifications.Deduplication

    # First check if status messages are enabled
    if WandererNotifier.Shared.Config.status_messages_enabled?() do
      uptime_seconds = calculate_uptime()
      days = div(uptime_seconds, 86_400)
      hours = div(rem(uptime_seconds, 86_400), 3600)
      minutes = div(rem(uptime_seconds, 3600), 60)
      seconds = rem(uptime_seconds, 60)
      formatted_uptime = "#{days}d #{hours}h #{minutes}m #{seconds}s"
      current_minute = div(:os.system_time(:second), 60)
      dedup_key = "status_report:#{current_minute}"

      case Deduplication.check(:system, dedup_key) do
        {:ok, :new} ->
          AppLogger.maintenance_info("📊 Status report sent | #{formatted_uptime} uptime")

          WandererNotifier.Domains.Notifications.Notifiers.StatusNotifier.send_status_message(
            "WandererNotifier Service Status",
            "Automated periodic status report."
          )

        {:ok, :duplicate} ->
          AppLogger.maintenance_info("📊 Status report skipped - duplicate")
      end
    else
      AppLogger.maintenance_info("📊 Status report skipped - disabled by config")
    end
  rescue
    e ->
      AppLogger.maintenance_error("📊 Status report failed",
        error: Exception.message(e)
      )
  end

  defp calculate_uptime do
    case :erlang.statistics(:wall_clock) do
      {total_wall_clock, _} ->
        div(total_wall_clock, 1000)
    end
  end
end
