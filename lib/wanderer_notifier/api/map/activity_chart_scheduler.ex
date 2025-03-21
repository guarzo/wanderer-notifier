defmodule WandererNotifier.Api.Map.ActivityChartScheduler do
  @moduledoc """
  Schedules and processes periodic character activity charts from Map API data.
  """
  use GenServer
  require Logger
  alias WandererNotifier.Api.Map.Client, as: MapClient
  alias WandererNotifier.Core.Config

  # Default interval is 24 hours (in milliseconds)
  @default_interval 24 * 60 * 60 * 1000

  # Chart types and their configurations
  @chart_configs [
    %{
      type: :activity_summary,
      title: "Character Activity Summary",
      description:
        "Top characters by connections, passages, and signatures in the last 24 hours.\nData is refreshed daily."
    }
    # Timeline and distribution charts removed
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

    Logger.info("Initializing Activity Chart Scheduler...")

    # Schedule first chart sending only if map tools are enabled
    if Config.map_tools_enabled?() do
      schedule_charts(interval)
      Logger.info("Activity Chart Scheduler initialized and scheduled")
    else
      Logger.info("Activity Chart Scheduler initialized but not scheduled (Map Tools disabled)")
    end

    # Initial state
    {:ok, %{interval: interval, last_sent: nil}}
  end

  @impl true
  def handle_cast(:send_all_charts, state) do
    # Send all charts only if map tools are enabled
    if Config.map_tools_enabled?() do
      # Send all charts
      _results = send_charts()

      # Update state with last sent timestamp
      {:noreply, %{state | last_sent: DateTime.utc_now()}}
    else
      Logger.info("Skipping manually triggered Activity Charts (Map Tools disabled)")
      {:noreply, state}
    end
  end

  @impl true
  def handle_call({:set_interval, interval_ms}, _from, state) do
    # Update interval in state
    new_state = %{state | interval: interval_ms}

    # Reschedule with new interval only if map tools are enabled
    if Config.map_tools_enabled?() do
      schedule_charts(interval_ms)
    else
      Logger.info("Not rescheduling Activity Charts (Map Tools disabled)")
    end

    {:reply, :ok, new_state}
  end

  @impl true
  def handle_info(:send_charts, state) do
    # Send charts only if map tools are enabled
    if Config.map_tools_enabled?() do
      Logger.info("Sending activity charts to Discord...")

      # Send charts
      _results = send_charts()

      # Schedule next run
      schedule_charts(state.interval)

      {:noreply, %{state | last_sent: DateTime.utc_now()}}
    else
      Logger.info("Skipping scheduled Activity Charts (Map Tools disabled)")
      {:noreply, state}
    end
  end

  # Helper Functions

  defp schedule_charts(interval) do
    # Only schedule if map tools are enabled
    if Config.map_tools_enabled?() do
      Process.send_after(self(), :send_charts, interval)
      Logger.debug("Scheduled next activity chart run in #{interval / 1000 / 60} minutes")
    else
      Logger.info("Not scheduling Activity Charts (Map Tools disabled)")
    end
  end

  # Get the channel ID for activity charts with proper fallback
  defp get_channel_id do
    channel_id = Config.discord_channel_id_for_activity_charts()

    # Use debug level for detailed channel variables, info level will show the actual ID being used
    Logger.debug("Using activity charts channel ID: #{channel_id}")
    channel_id
  end

  defp send_charts do
    Logger.info("Sending scheduled activity charts to Discord")

    # Get activity data first
    activity_data_result = get_activity_data()

    case activity_data_result do
      {:ok, activity_data} ->
        # Get the channel ID for activity charts
        channel_id = get_channel_id()
        Logger.info("Sending activity charts to Discord channel: #{channel_id}")

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
                      config.title,
                      "activity_summary",
                      config.description,
                      channel_id
                    )

                  :activity_timeline ->
                    case WandererNotifier.ChartService.ActivityChartAdapter.generate_activity_timeline_chart(
                           activity_data
                         ) do
                      {:ok, url} ->
                        WandererNotifier.ChartService.send_chart_to_discord(
                          url,
                          "Activity Timeline",
                          "Activity over time",
                          channel_id
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
