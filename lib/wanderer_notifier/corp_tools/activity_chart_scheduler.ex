defmodule WandererNotifier.CorpTools.ActivityChartScheduler do
  @moduledoc """
  Schedules and sends character activity charts to Discord on a regular basis.
  """
  use GenServer
  require Logger
  alias WandererNotifier.CorpTools.ActivityChartAdapter

  # Default interval is 24 hours (in milliseconds)
  @default_interval 24 * 60 * 60 * 1000

  # Chart types and their configurations
  @chart_configs [
    %{
      type: :activity_summary,
      title: "Character Activity Summary",
      description: "Top 10 most active characters by connections, passages, and signatures"
    },
    %{
      type: :activity_timeline,
      title: "Character Activity Timeline",
      description: "Activity trends over time for the top 5 most active characters"
    },
    %{
      type: :activity_distribution,
      title: "Activity Type Distribution",
      description: "Distribution of activity types across all characters"
    }
  ]

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
    # Get interval from options or use default
    interval = Keyword.get(opts, :interval, @default_interval)

    # Schedule first chart sending
    schedule_charts(interval)

    # Initial state
    {:ok, %{interval: interval, last_sent: nil}}
  end

  @impl true
  def handle_cast(:send_all_charts, state) do
    # Send all charts
    _results = send_charts()

    # Update state with last sent timestamp
    {:noreply, %{state | last_sent: DateTime.utc_now()}}
  end

  @impl true
  def handle_call({:set_interval, interval_ms}, _from, state) do
    # Update interval in state
    new_state = %{state | interval: interval_ms}

    # Reschedule with new interval
    schedule_charts(interval_ms)

    {:reply, :ok, new_state}
  end

  @impl true
  def handle_info(:send_charts, state) do
    Logger.info("Sending activity charts to Discord...")

    # Send charts
    _results = send_charts()

    # Schedule next run
    schedule_charts(state.interval)

    {:noreply, %{state | last_sent: DateTime.utc_now()}}
  end

  # Helper Functions

  defp schedule_charts(interval) do
    Process.send_after(self(), :send_charts, interval)
  end

  defp send_charts do
    Logger.info("Sending scheduled activity charts to Discord")

    # Send each chart and collect results
    results = Enum.map(@chart_configs, fn config ->
      result = ActivityChartAdapter.send_chart_to_discord(
        config.type,
        config.title,
        config.description
      )

      {config.type, result}
    end)

    # Log results
    Enum.each(results, fn {type, result} ->
      case result do
        :ok ->
          Logger.info("Successfully sent #{type} chart to Discord")
        {:error, reason} ->
          Logger.error("Failed to send #{type} chart to Discord: #{inspect(reason)}")
      end
    end)

    results
  end
end 