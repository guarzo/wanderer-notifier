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

  defp generate_service_status_report do
    alias WandererNotifier.Logger.Logger, as: AppLogger
    alias WandererNotifier.Notifiers.Helpers.Deduplication

    uptime_seconds = calculate_uptime()
    days = div(uptime_seconds, 86_400)
    hours = div(rem(uptime_seconds, 86_400), 3600)
    minutes = div(rem(uptime_seconds, 3600), 60)
    seconds = rem(uptime_seconds, 60)
    formatted_uptime = "#{days}d #{hours}h #{minutes}m #{seconds}s"
    current_day = div(:os.system_time(:second), 86_400)
    dedup_key = "status_report:#{current_day}"

    case Deduplication.check_and_mark(dedup_key) do
      {:ok, :new} ->
        AppLogger.maintenance_info("Service status report",
          uptime: formatted_uptime,
          status: "operational"
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
