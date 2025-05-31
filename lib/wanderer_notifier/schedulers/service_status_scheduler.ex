defmodule WandererNotifier.Schedulers.ServiceStatusScheduler do
  @moduledoc """
  Scheduler responsible for generating periodic service status reports.
  """
  use GenServer
  alias WandererNotifier.Logger.Logger, as: AppLogger

  @behaviour WandererNotifier.Schedulers.Scheduler

  @impl true
  # 1 hour
  def config, do: %{type: :interval, spec: 3_600_000}

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
    schedule_next_run()
    {:ok, %{}}
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

    schedule_next_run()
    {:noreply, state}
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
    alias WandererNotifier.Notifications.Deduplication

    # First check if status messages are disabled
    if WandererNotifier.Config.status_messages_disabled?() do
      AppLogger.maintenance_info("📊 Status report skipped - disabled by config")
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
          AppLogger.maintenance_info("📊 Status report sent | #{formatted_uptime} uptime")

          WandererNotifier.Notifiers.StatusNotifier.send_status_message(
            "WandererNotifier Service Status",
            "Automated periodic status report."
          )

        {:ok, :duplicate} ->
          AppLogger.maintenance_info("📊 Status report skipped - duplicate")
      end
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

      _ ->
        0
    end
  end
end
