defmodule WandererNotifier.CorpTools.ChartScheduler do
  @moduledoc """
  Schedules and sends charts to Discord on a regular basis.
  """
  use GenServer
  require Logger
  alias WandererNotifier.CorpTools.JSChartAdapter
  alias WandererNotifier.CorpTools.Client, as: CorpToolsClient

  # Default interval is 24 hours (in milliseconds)
  @default_interval 24 * 60 * 60 * 1000

  # Chart types and their configurations
  @chart_configs [
    %{
      type: :damage_final_blows,
      title: "Damage and Final Blows Analysis",
      description: "Top 20 characters by damage done and final blows"
    },
    %{
      type: :combined_losses,
      title: "Combined Losses Analysis",
      description: "Top 10 characters by losses value and count"
    },
    %{
      type: :kill_activity,
      title: "Kill Activity Over Time",
      description: "Kill activity trend over time"
    }
  ]

  # Client API

  @doc """
  Starts the chart scheduler.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Manually triggers sending of all charts.
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
    # Check if TPS data is available
    case CorpToolsClient.get_tps_data() do
      {:ok, _data} ->
        # Send all charts
        results = send_charts()

        # Update state with last sent timestamp
        {:noreply, %{state | last_sent: DateTime.utc_now()}}

      {:loading, _} ->
        Logger.warning("Cannot send charts: TPS data is still loading")
        {:noreply, state}

      {:error, reason} ->
        Logger.error("Cannot send charts: #{inspect(reason)}")
        {:noreply, state}
    end
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
    # Send all charts
    send_charts()

    # Schedule next sending
    schedule_charts(state.interval)

    # Update state with last sent timestamp
    {:noreply, %{state | last_sent: DateTime.utc_now()}}
  end

  # Helper Functions

  defp schedule_charts(interval) do
    Process.send_after(self(), :send_charts, interval)
  end

  defp send_charts do
    Logger.info("Sending scheduled charts to Discord")

    # Send each chart and collect results
    results = Enum.map(@chart_configs, fn config ->
      result = JSChartAdapter.send_chart_to_discord(
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
