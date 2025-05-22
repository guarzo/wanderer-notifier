defmodule WandererNotifier.Schedulers.ServiceStatusScheduler do
  @moduledoc """
  Scheduler responsible for generating periodic service status reports.
  """
  alias WandererNotifier.Logger.Logger, as: AppLogger

  @behaviour WandererNotifier.Schedulers.Scheduler

  @impl true
  def config, do: %{type: :interval, spec: WandererNotifier.Config.service_status_interval()}

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


  def init(opts) do
    {:ok, opts}
  end

  defp generate_service_status_report do
    alias WandererNotifier.Notifications.Deduplication

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
        AppLogger.maintenance_info("Service status report",
          uptime: formatted_uptime,
          status: "operational"
        )

        WandererNotifier.Notifiers.StatusNotifier.send_status_message(
          "WandererNotifier Service Status",
          "Automated periodic status report."
        )

      {:ok, :duplicate} ->
        AppLogger.maintenance_info("Service status notification skipped (duplicate)",
          action: "skipping_duplicate"
        )
    end
  rescue
    e ->
      AppLogger.maintenance_error("Error generating service status report",
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
