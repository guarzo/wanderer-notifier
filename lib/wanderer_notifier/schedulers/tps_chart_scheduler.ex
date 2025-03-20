defmodule WandererNotifier.Schedulers.TPSChartScheduler do
  @moduledoc """
  Schedules TPS chart generation and sending to Discord.
  
  This scheduler is responsible for TPS (Time, Pilots, Ships) charts using the TPSChartAdapter.
  It runs at a specific time each day (default 12:00 UTC).
  """
  
  require WandererNotifier.Schedulers.Factory
  require Logger
  
  alias WandererNotifier.ChartService.TPSChartAdapter
  alias WandererNotifier.CorpTools.CorpToolsClient
  
  # Create a time-based scheduler with specific configuration
  WandererNotifier.Schedulers.Factory.create_scheduler(
    type: :time,
    default_hour: WandererNotifier.Core.Config.Timings.tps_chart_hour(),
    default_minute: WandererNotifier.Core.Config.Timings.tps_chart_minute(),
    hour_env_var: :tps_chart_schedule_hour,
    minute_env_var: :tps_chart_schedule_minute,
    enabled_check: &WandererNotifier.Core.Config.corp_tools_enabled?/0
  )
  
  @impl true
  def execute(state) do
    Logger.info("Executing TPS chart generation and sending to Discord")
    
    result =
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
          
          {:ok, results}
          
        {:error, reason} = error ->
          Logger.error("Failed to refresh TPS data: #{inspect(reason)}")
          error
      end
    
    case result do
      {:ok, results} -> {:ok, results, state}
      {:error, reason} -> {:error, reason, state}
    end
  end
end