defmodule WandererNotifier.Service.TPSChartScheduler do
  @moduledoc """
  Schedules TPS chart generation and sending to Discord.

  This scheduler is responsible for TPS (Time, Pilots, Ships) charts using the TPSChartAdapter.
  It is different from the ChartScheduler which handles JavaScript-based charts.
  """
  use GenServer
  require Logger

  alias WandererNotifier.CorpTools.TPSChartAdapter
  alias WandererNotifier.CorpTools.Client, as: CorpToolsClient

  # Default schedule: Send charts once a day at 12:00 UTC
  @default_schedule_hour 12
  @default_schedule_minute 0

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    Logger.info("Initializing TPS Chart Scheduler...")

    # Schedule the first run
    schedule_next_run()

    {:ok, %{last_run: nil}}
  end

  @impl true
  def handle_info(:send_charts, state) do
    Logger.info("Running scheduled TPS chart generation and sending to Discord")

    # First refresh the TPS data
    case CorpToolsClient.refresh_tps_data() do
      :ok ->
        Logger.info("TPS data refreshed successfully, generating and sending charts")
        # Wait a moment for the data to be processed
        Process.sleep(5000)
        # Send all charts to Discord
        results = TPSChartAdapter.send_all_charts_to_discord()

        # Log the results
        Enum.each(results, fn {chart_type, result} ->
          case result do
            :ok ->
              Logger.info("Successfully sent #{chart_type} chart to Discord")
            {:error, reason} ->
              Logger.error("Failed to send #{chart_type} chart to Discord: #{inspect(reason)}")
          end
        end)

      {:error, reason} ->
        Logger.error("Failed to refresh TPS data: #{inspect(reason)}")
    end

    # Schedule the next run
    schedule_next_run()

    {:noreply, %{state | last_run: DateTime.utc_now()}}
  end

  # Schedule the next run at the configured time
  defp schedule_next_run do
    now = DateTime.utc_now()

    # Get the configured schedule time (hour and minute)
    hour = Application.get_env(:wanderer_notifier, :tps_chart_schedule_hour, @default_schedule_hour)
    minute = Application.get_env(:wanderer_notifier, :tps_chart_schedule_minute, @default_schedule_minute)

    # Calculate the next run time
    next_run = calculate_next_run(now, hour, minute)

    # Calculate milliseconds until next run
    milliseconds_until_next_run = DateTime.diff(next_run, now, :millisecond)

    Logger.info("Scheduled next TPS chart run at #{DateTime.to_string(next_run)} (in #{div(milliseconds_until_next_run, 60000)} minutes)")

    # Schedule the next run
    Process.send_after(self(), :send_charts, milliseconds_until_next_run)
  end

  # Calculate the next run time based on the current time and the scheduled hour and minute
  defp calculate_next_run(now, hour, minute) do
    # Create a datetime for today at the scheduled time
    today_scheduled = %{now | hour: hour, minute: minute, second: 0, microsecond: {0, 0}}

    # If the scheduled time for today has already passed, schedule for tomorrow
    if DateTime.compare(today_scheduled, now) == :lt do
      # Add 1 day
      DateTime.add(today_scheduled, 86400, :second)
    else
      today_scheduled
    end
  end

  # Manual trigger for sending charts
  def send_charts_now do
    GenServer.cast(__MODULE__, :send_charts_now)
  end

  @impl true
  def handle_cast(:send_charts_now, state) do
    Logger.info("Manually triggered TPS chart generation and sending to Discord")

    # Send the message to self to trigger the chart sending process
    send(self(), :send_charts)

    {:noreply, state}
  end
end
