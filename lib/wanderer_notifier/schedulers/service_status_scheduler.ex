defmodule WandererNotifier.Schedulers.ServiceStatusScheduler do
  @moduledoc """
  Scheduler responsible for generating periodic service status reports.
  """
  use GenServer
  alias WandererNotifier.Logger.Logger, as: AppLogger
  alias WandererNotifier.Constants

  @behaviour WandererNotifier.Schedulers.Scheduler

  @impl true
  def config, do: %{type: :interval, spec: Constants.service_status_interval()}

  @impl true
  def run do
    start_time = System.monotonic_time()
    generate_service_status_report(start_time)
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
    schedule_next_run()
    {:ok, %{last_run: nil, consecutive_errors: 0}}
  end

  @impl GenServer
  def handle_info(:run_status_report, state) do
    start_time = System.monotonic_time()

    case generate_service_status_report(start_time) do
      :ok ->
        new_state = %{
          state
          | last_run: DateTime.utc_now(),
            consecutive_errors: 0
        }

        schedule_next_run()
        {:noreply, new_state}

      {:error, reason} ->
        consecutive_errors = state.consecutive_errors + 1
        backoff = calculate_backoff(consecutive_errors)

        AppLogger.scheduler_error("Status report failed",
          error: inspect(reason),
          consecutive_errors: consecutive_errors,
          backoff_ms: backoff
        )

        schedule_next_run_with_backoff(backoff)
        {:noreply, %{state | consecutive_errors: consecutive_errors}}
    end
  end

  @impl GenServer
  def handle_info(_msg, state) do
    {:noreply, state}
  end

  defp schedule_next_run do
    %{spec: interval} = config()
    Process.send_after(self(), :run_status_report, interval)
  end

  defp schedule_next_run_with_backoff(backoff) do
    Process.send_after(self(), :run_status_report, backoff)
  end

  defp calculate_backoff(consecutive_errors) do
    base = Constants.base_backoff()
    max = Constants.max_backoff()
    calculated = base * :math.pow(2, consecutive_errors - 1)
    min(trunc(calculated), max)
  end

  defp generate_service_status_report(start_time) do
    alias WandererNotifier.Notifications.Deduplication

    # First check if status messages are disabled
    if WandererNotifier.Config.status_messages_disabled?() do
      AppLogger.maintenance_info("📊 Status report skipped - disabled by config")
      :ok
    else
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
          duration = System.monotonic_time() - start_time

          AppLogger.maintenance_info("📊 Status report sent",
            uptime: formatted_uptime,
            duration_ms: System.convert_time_unit(duration, :native, :millisecond)
          )

          WandererNotifier.Notifiers.StatusNotifier.send_status_message(
            "WandererNotifier Service Status",
            "Automated periodic status report."
          )

          :ok

        {:ok, :duplicate} ->
          AppLogger.maintenance_info("📊 Status report skipped - duplicate")
          :ok

        {:error, reason} ->
          AppLogger.maintenance_error("📊 Status report failed - deduplication error",
            error: inspect(reason)
          )

          {:error, reason}
      end
    end
  rescue
    e ->
      AppLogger.maintenance_error("📊 Status report failed",
        error: Exception.message(e),
        stacktrace: Exception.format_stacktrace(__STACKTRACE__)
      )

      {:error, e}
  end

  defp calculate_uptime do
    case :erlang.statistics(:wall_clock) do
      {total_wall_clock, _} ->
        div(total_wall_clock, 1000)

      _ ->
        0
    end
  end
end
