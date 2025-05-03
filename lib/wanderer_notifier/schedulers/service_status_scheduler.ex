defmodule WandererNotifier.Schedulers.ServiceStatusScheduler do
  @moduledoc """
  Scheduler responsible for generating periodic service status reports.
  """
  @behaviour WandererNotifier.Schedulers.Scheduler

  use WandererNotifier.Schedulers.IntervalScheduler,
    name: __MODULE__,
    initialize_error_handling: true

  # Interval is now configured via the Timings module

  alias WandererNotifier.Config
  alias WandererNotifier.Logger.Logger, as: AppLogger
  alias WandererNotifier.Notifiers.Helpers.Deduplication

  @impl true
  def execute(state) do
    # Get the current uptime if available, or calculate it
    uptime_seconds = Map.get(state, :uptime_seconds, calculate_uptime())

    # Format the uptime for display
    days = div(uptime_seconds, 86_400)
    hours = div(rem(uptime_seconds, 86_400), 3600)
    minutes = div(rem(uptime_seconds, 3600), 60)
    seconds = rem(uptime_seconds, 60)

    formatted_uptime = "#{days}d #{hours}h #{minutes}m #{seconds}s"

    # Create a deduplication key based on a time window
    # We'll use the current day as part of the key to deduplicate within the same day
    current_day = div(:os.system_time(:second), 86_400)
    dedup_key = "status_report:#{current_day}"

    # Check if we've already sent a status report in this time window
    case Deduplication.check_and_mark(dedup_key) do
      {:ok, :new} ->
        AppLogger.maintenance_info("Service status report",
          uptime: formatted_uptime,
          status: "operational"
        )

        # Update state with the latest uptime
        new_state = Map.put(state, :uptime_seconds, uptime_seconds + 86_400)

        # Return success
        {:ok, %{uptime: formatted_uptime}, new_state}

      {:ok, :duplicate} ->
        AppLogger.maintenance_info("Service status notification skipped (duplicate)",
          action: "skipping_duplicate"
        )

        # Update state with the latest uptime anyway
        new_state = Map.put(state, :uptime_seconds, uptime_seconds + 86_400)

        {:ok, %{status: :duplicate}, new_state}
    end
  rescue
    e ->
      # Handle any unexpected errors
      AppLogger.maintenance_error("Error generating service status report",
        error: Exception.message(e)
      )

      {:error, e, state}
  end

  @impl true
  def enabled?, do: true

  @impl true
  def get_config do
    %{
      interval_ms: Config.service_status_interval(),
      enabled: true,
      last_execution: nil
    }
  end

  # Calculate the application uptime in seconds
  defp calculate_uptime do
    case :erlang.statistics(:wall_clock) do
      {total_wall_clock, _} ->
        # Convert milliseconds to seconds
        div(total_wall_clock, 1000)

      _ ->
        0
    end
  end
end
