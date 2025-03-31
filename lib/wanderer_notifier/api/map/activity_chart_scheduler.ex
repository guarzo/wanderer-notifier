defmodule WandererNotifier.Api.Map.ActivityChartScheduler do
  @moduledoc """
  Schedules and processes periodic character activity charts from Map API data.
  """
  use GenServer
  require Logger
  alias WandererNotifier.Api.Map.Client, as: MapClient
  alias WandererNotifier.ChartService.ActivityChartAdapter
  alias WandererNotifier.Config.Features
  alias WandererNotifier.Config.Notifications
  alias WandererNotifier.Config.SystemTracking
  alias WandererNotifier.Core.Logger, as: AppLogger
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
      channel_id = get_channel_id()
      # Schedule next run using the interval from state
      Process.send_after(self(), {:generate_charts, %{channel_id: channel_id}}, @default_interval)
      AppLogger.api_debug("Scheduled next activity chart run for channel: #{channel_id}")
    else
      AppLogger.api_info("Not scheduling Activity Charts (Map Charts disabled)")
    end
  end

  # Get the channel ID for activity charts with proper fallback
  defp get_channel_id do
    Notifications.get_discord_channel_id_for(:activity_charts)
  end

  defp send_charts do
    AppLogger.api_info("Sending scheduled activity charts to Discord")

    # Get activity data first
    activity_data_result = get_activity_data()
    process_activity_data(activity_data_result)
  end

  defp process_activity_data({:ok, activity_data}) do
    # Get the channel ID for activity charts
    channel_id = get_channel_id()
    AppLogger.api_info("Sending activity charts to Discord channel: #{channel_id}")

    # Send each chart and collect results
    results = generate_charts(activity_data, channel_id)

    # Log the results
    log_chart_results(results)

    # Return the results
    results
  end

  defp process_activity_data({:error, reason}) do
    AppLogger.api_error("Failed to retrieve activity data: #{inspect(reason)}")
    []
  end

  defp generate_charts(activity_data, channel_id) do
    Enum.map(@chart_configs, fn config ->
      AppLogger.api_info("Generating chart: #{config.type} - #{config.title}")
      {config.type, generate_chart(config, activity_data, channel_id)}
    end)
  end

  defp generate_chart(config, activity_data, channel_id) do
    case config.type do
      :activity_summary ->
        generate_activity_summary(activity_data, config, channel_id)

      :activity_timeline ->
        generate_activity_timeline(activity_data, channel_id)

      _ ->
        {:error, "Unknown chart type: #{config.type}"}
    end
  rescue
    e ->
      error_message = "Chart generation crashed: #{inspect(e)}"
      AppLogger.api_error(error_message)
      {:error, error_message}
  catch
    kind, reason ->
      error_message = "Chart generation threw #{kind}: #{inspect(reason)}"
      AppLogger.api_error(error_message)
      {:error, error_message}
  end

  defp generate_activity_summary(activity_data, config, channel_id) do
    ActivityChartAdapter.send_chart_to_discord(
      activity_data,
      config.title,
      "activity_summary",
      config.description,
      channel_id
    )
  end

  defp generate_activity_timeline(_activity_data, _channel_id) do
    AppLogger.api_warn("Activity Timeline chart has been removed", %{})
    {:error, "Activity Timeline chart has been removed"}
  end

  defp log_chart_results(results) do
    # Log individual results
    Enum.each(results, &log_chart_result/1)

    # Log summary
    success_count = Enum.count(results, fn {_, result} -> match?({:ok, _, _}, result) end)
    AppLogger.api_info("Chart sending complete: #{success_count}/#{length(results)} successful")
  end

  defp log_chart_result({type, {:ok, url, title}}) do
    AppLogger.api_info("Successfully sent #{type} chart to Discord: #{title}")
    AppLogger.api_debug("Chart URL: #{String.slice(url, 0, 100)}...")
  end

  defp log_chart_result({type, {:error, reason}}) do
    AppLogger.api_error("Failed to send #{type} chart to Discord: #{inspect(reason)}")
  end

  defp log_chart_result({type, result}) do
    AppLogger.api_error("Unexpected result for #{type} chart: #{inspect(result)}")
  end

  # Helper to get activity data from Map API
  defp get_activity_data do
    # Get config
    config = get_map_config()
    map_name = Map.get(config, :map_name)

    if is_nil(map_name) do
      AppLogger.api_warn("Map name not configured for activity data")
      {:error, "Map name not configured"}
    else
      AppLogger.api_info("Fetching character activity data for map: #{map_name}")
      MapClient.get_character_activity(map_name)
    end
  end

  defp get_map_config do
    case SystemTracking.get_map_config() do
      {:ok, config} -> config
      _ -> %{}
    end
  end
end
