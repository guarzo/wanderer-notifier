defmodule WandererNotifier.Api.Map.ActivityChartScheduler do
  @moduledoc """
  Schedules and processes periodic character activity charts from Map API data.
  """
  use GenServer
  require Logger
  alias WandererNotifier.Api.Map.Client, as: MapClient
  alias WandererNotifier.ChartService.ActivityChartAdapter
  alias WandererNotifier.Config.Features
  alias WandererNotifier.Config.Timings
  alias WandererNotifier.Logger.Logger, as: AppLogger

  # Client API

  @doc """
  Starts the activity chart scheduler.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Manually triggers sending of all activity charts.
  """
  def send_all_charts do
    GenServer.cast(__MODULE__, :send_all_charts)
  end

  @doc """
  Changes the interval for automatic chart sending.
  """
  def set_interval(interval_ms) when is_integer(interval_ms) and interval_ms > 0 do
    GenServer.call(__MODULE__, {:set_interval, interval_ms})
  end

  # Server Callbacks

  @impl true
  def init(opts) do
    # Get interval from options or use Timings module
    interval = Keyword.get(opts, :interval, Timings.activity_chart_interval())

    AppLogger.api_info("Initializing Activity Chart Scheduler...")

    # Schedule first chart sending only if map charts are enabled
    if Features.map_charts_enabled?() do
      schedule_charts()
      AppLogger.api_info("Activity Chart Scheduler initialized and scheduled")
    else
      AppLogger.api_info(
        "Activity Chart Scheduler initialized but not scheduled (Map Charts disabled)"
      )
    end

    # Initial state
    {:ok, %{interval: interval, last_sent: nil}}
  end

  @impl true
  def handle_cast(:send_all_charts, state) do
    # Send all charts only if map charts are enabled
    if Features.map_charts_enabled?() do
      # Send all charts
      _results = send_charts()

      # Update state with last sent timestamp
      {:noreply, %{state | last_sent: DateTime.utc_now()}}
    else
      AppLogger.api_info("Skipping manually triggered Activity Charts (Map Charts disabled)")
      {:noreply, state}
    end
  end

  @impl true
  def handle_call({:set_interval, interval_ms}, _from, state) do
    # Update interval in state
    new_state = %{state | interval: interval_ms}

    # Reschedule with new interval only if map charts are enabled
    if Features.map_charts_enabled?() do
      schedule_charts()
    else
      AppLogger.api_info("Not rescheduling Activity Charts (Map Charts disabled)")
    end

    {:reply, :ok, new_state}
  end

  @impl true
  def handle_info({:generate_charts, _opts}, state) do
    # Send charts only if map charts are enabled
    if Features.map_charts_enabled?() do
      AppLogger.api_info("Sending activity charts to Discord...")

      # Send charts
      _results = send_charts()

      # Schedule next run
      schedule_charts()

      {:noreply, %{state | last_sent: DateTime.utc_now()}}
    else
      AppLogger.api_info("Skipping scheduled Activity Charts (Map Charts disabled)")
      {:noreply, state}
    end
  end

  # Helper Functions

  defp schedule_charts do
    # Only schedule if map charts are enabled
    if Features.map_charts_enabled?() do
      # Use Timings module for interval
      interval = Timings.activity_chart_interval()

      # Schedule next run using the interval
      Process.send_after(self(), {:generate_charts, %{}}, interval)
      AppLogger.api_debug("Scheduled next activity chart run")
    else
      AppLogger.api_info("Not scheduling Activity Charts (Map Charts disabled)")
    end
  end

  defp send_charts do
    AppLogger.api_info("Sending scheduled activity charts to Discord")

    # Get activity data first
    case get_activity_data() do
      {:ok, activity_data} ->
        # Use the same path as debug endpoint
        case ActivityChartAdapter.generate_and_send_activity_chart(activity_data) do
          {:ok, result} ->
            AppLogger.api_info("Successfully sent activity chart to Discord")
            [result]

          {:error, reason} ->
            AppLogger.api_error("Failed to send activity chart to Discord",
              error: inspect(reason)
            )

            []
        end

      {:error, reason} ->
        AppLogger.api_error("Failed to retrieve activity data: #{inspect(reason)}")
        []
    end
  end

  defp get_activity_data do
    AppLogger.api_info("Fetching character activity data")
    MapClient.get_character_activity(nil)
  end
end
