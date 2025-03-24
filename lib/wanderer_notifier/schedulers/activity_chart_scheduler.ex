defmodule WandererNotifier.Schedulers.ActivityChartScheduler do
  @moduledoc """
  Schedules and processes periodic character activity charts from Map API data.

  This scheduler is responsible for character activity charts at regular intervals.
  """

  require WandererNotifier.Schedulers.Factory
  require Logger
alias WandererNotifier.Logger, as: AppLogger

  alias WandererNotifier.Api.Map.CharactersClient
  alias WandererNotifier.ChartService.ActivityChartAdapter
  alias WandererNotifier.Core.Config.Timings

  # Get the default interval from Timings module
  @default_interval Timings.activity_chart_interval()

  # Chart types and their configurations
  @chart_configs [
    %{
      type: :activity_summary,
      title: "Character Activity",
      description: "Top 5 most active characters showing connections, passages, and signatures"
    }
    # activity_timeline and activity_distribution charts have been removed
  ]

  # Create an interval-based scheduler with specific configuration
  WandererNotifier.Schedulers.Factory.create_scheduler(__MODULE__, 
    type: :interval,
    default_interval: @default_interval,
    enabled_check: &WandererNotifier.Core.Config.map_charts_enabled?/0
  )

  @impl true
  def execute(state) do
    AppLogger.scheduler_info("Executing character activity chart generation and sending to Discord")

    # Get activity data and process it if available
    case get_activity_data() do
      {:ok, activity_data} ->
        results = process_chart_configs(activity_data)
        process_results(results, state)

      {:error, reason} ->
        AppLogger.scheduler_error("Failed to retrieve activity data: #{inspect(reason)}")
        {:error, reason, state}
    end
  end

  # Process each chart config and generate charts
  defp process_chart_configs(activity_data) do
    Enum.map(@chart_configs, fn config ->
      AppLogger.scheduler_info("Generating chart: #{config.type} - #{config.title}")
      result = generate_chart(config, activity_data)
      {config.type, result}
    end)
  end

  # Generate a chart based on its type and configuration
  defp generate_chart(config, activity_data) do
    try do
      generate_chart_by_type(config.type, activity_data, config.title)
    rescue
      e ->
        error_message = "Chart generation crashed: #{inspect(e)}"
        AppLogger.scheduler_error(error_message)
        {:error, error_message}
    catch
      kind, reason ->
        error_message = "Chart generation threw #{kind}: #{inspect(reason)}"
        AppLogger.scheduler_error(error_message)
        {:error, error_message}
    end
  end

  # Handle different chart types
  defp generate_chart_by_type(:activity_summary, activity_data, title) do
    ActivityChartAdapter.send_chart_to_discord(activity_data, title)
  end

  defp generate_chart_by_type(unknown_type, _activity_data, _title) do
    {:error, "Unknown chart type: #{unknown_type}"}
  end

  # Process results and return appropriate response
  defp process_results(results, state) do
    # Log results
    Enum.each(results, &log_chart_result/1)

    # Count successful charts
    success_count = Enum.count(results, fn {_, result} -> match?({:ok, _, _}, result) end)
    AppLogger.scheduler_info("Chart sending complete: #{success_count}/#{length(results)} successful")

    {:ok, results, state}
  end

  # Log the result of each chart generation
  defp log_chart_result({type, result}) do
    case result do
      {:ok, url, title} ->
        AppLogger.scheduler_info("Successfully sent #{type} chart to Discord: #{title}")
        AppLogger.scheduler_debug("Chart URL: #{String.slice(url, 0, 100)}...")

      {:error, reason} ->
        AppLogger.scheduler_error("Failed to send #{type} chart to Discord: #{inspect(reason)}")

      _ ->
        AppLogger.scheduler_error("Unexpected result for #{type} chart: #{inspect(result)}")
    end
  end

  # Helper to get activity data from Map API
  defp get_activity_data do
    # Use the new CharactersClient module to fetch activity data
    # This handles slug/map name resolution internally
    AppLogger.scheduler_info("Fetching character activity data")
    CharactersClient.get_character_activity()
  end
end
