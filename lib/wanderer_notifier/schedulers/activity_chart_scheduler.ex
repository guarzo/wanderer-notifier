defmodule WandererNotifier.Schedulers.ActivityChartScheduler do
  @moduledoc """
  Schedules and processes periodic character activity charts from Map API data.
  
  This scheduler is responsible for character activity charts at regular intervals.
  """
  
  require WandererNotifier.Schedulers.Factory
  require Logger
  
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
  ]
  
  # Create an interval-based scheduler with specific configuration
  WandererNotifier.Schedulers.Factory.create_scheduler(
    type: :interval,
    default_interval: @default_interval,
    enabled_check: &WandererNotifier.Core.Config.map_tools_enabled?/0
  )
  
  @impl true
  def execute(state) do
    Logger.info("Executing character activity chart generation and sending to Discord")
    
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
                    ActivityChartAdapter.send_chart_to_discord(activity_data, config.title)
                    
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
        
        {:ok, results, state}
        
      {:error, reason} ->
        Logger.error("Failed to retrieve activity data: #{inspect(reason)}")
        {:error, reason, state}
    end
  end
  
  # Helper to get activity data from Map API
  defp get_activity_data do
    # Use the new CharactersClient module to fetch activity data
    # This handles slug/map name resolution internally
    Logger.info("Fetching character activity data")
    CharactersClient.get_character_activity()
  end
end