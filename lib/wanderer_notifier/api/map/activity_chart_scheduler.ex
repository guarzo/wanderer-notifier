defmodule WandererNotifier.Api.Map.ActivityChartScheduler do
  @moduledoc """
  Schedules and processes periodic character activity charts from Map API data.
  """
  use GenServer
  require Logger
  alias WandererNotifier.Api.Map.Client, as: MapClient

  # Default interval is 24 hours (in milliseconds)
  @default_interval 24 * 60 * 60 * 1000

  # Chart types and their configurations
  @chart_configs [
    %{
      type: :activity_summary,
      title: "Character Activity",
      description: "Top 5 most active characters showing connections, passages, and signatures"
    },
    %{
      type: :activity_timeline,
      title: "Activity Over Time",
      description: "Trends of connections, passages, and signatures over time"
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

    # Get activity data first
    activity_data_result = get_activity_data()

    case activity_data_result do
      {:ok, activity_data} ->
        # Send each chart and collect results
        results =
          Enum.map(@chart_configs, fn config ->
            Logger.info("Generating chart: #{config.type} - #{config.title}")

            # Add a try/rescue block to catch any unexpected errors
            result =
              try do
                case config.type do
                  :activity_summary ->
                    WandererNotifier.ChartService.ActivityChartAdapter.send_chart_to_discord(
                      activity_data,
                      config.title
                    )

                  :activity_timeline ->
                    case WandererNotifier.ChartService.ActivityChartAdapter.generate_activity_timeline_chart(
                           activity_data
                         ) do
                      {:ok, url} ->
                        WandererNotifier.ChartService.send_chart_to_discord(
                          url,
                          "Activity Timeline",
                          "Activity over time"
                        )

                      error ->
                        error
                    end

                  _ ->
                    {:error, "Unknown chart type: #{config.type}"}
                end
              rescue
                e ->
                  error_message = "Chart generation crashed: #{inspect(e)}"
                  Logger.error(error_message)
                  {:error, error_message}
              catch
                kind, reason ->
                  error_message = "Chart generation threw #{kind}: #{inspect(reason)}"
                  Logger.error(error_message)
                  {:error, error_message}
              end

            {config.type, result}
          end)

        # Log results
        Enum.each(results, fn {type, result} ->
          case result do
            {:ok, url, title} ->
              Logger.info("Successfully sent #{type} chart to Discord: #{title}")
              Logger.debug("Chart URL: #{String.slice(url, 0, 100)}...")

            {:error, reason} ->
              Logger.error("Failed to send #{type} chart to Discord: #{inspect(reason)}")

            _ ->
              Logger.error("Unexpected result for #{type} chart: #{inspect(result)}")
          end
        end)

        success_count = Enum.count(results, fn {_, result} -> match?({:ok, _, _}, result) end)
        Logger.info("Chart sending complete: #{success_count}/#{length(results)} successful")

        results

      {:error, reason} ->
        Logger.error("Failed to retrieve activity data: #{inspect(reason)}")
        []
    end
  end

  # Helper to get activity data from Map API
  defp get_activity_data do
    # Get config
    config = Application.get_env(:wanderer_notifier, WandererNotifier.Map) || %{}
    map_name = Map.get(config, :map_name)

    if is_nil(map_name) do
      Logger.warning("Map name not configured for activity data")
      {:error, "Map name not configured"}
    else
      Logger.info("Fetching character activity data for map: #{map_name}")
      MapClient.get_character_activity(map_name)
    end
  end
end
