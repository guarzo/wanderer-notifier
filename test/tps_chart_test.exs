defmodule WandererNotifier.TPSChartTest do
  @moduledoc """
  Test script for TPS chart generation.

  ## Usage

  Run with: `mix run test/tps_chart_test.exs`

  This script:
  1. Fetches TPS data from the API
  2. Attempts to generate charts with the TPS data
  3. Reports results
  """

  alias WandererNotifier.CorpTools.CorpToolsClient
  alias WandererNotifier.CorpTools.ChartService
  alias WandererNotifier.CorpTools.ChartTypes

  def run do
    IO.puts("Initializing chart service...")
    # Make sure Jason is loaded
    Application.ensure_all_started(:jason)

    # Initialize chart service directly
    ChartService.init()

    IO.puts("Fetching TPS data...")

    case CorpToolsClient.get_tps_data() do
      {:ok, tps_data} ->
        IO.puts("TPS data fetched successfully")

        # Generate damage_final_blows chart
        IO.puts("\nGenerating damage_final_blows chart...")

        case ChartService.generate_chart(ChartTypes.damage_final_blows(), tps_data) do
          {:ok, chart_path} ->
            IO.puts("Chart generated successfully at: #{chart_path}")
            IO.puts("Chart URL: file://#{chart_path}")

          {:error, reason} ->
            IO.puts("Failed to generate chart: #{inspect(reason)}")
        end

        # Log TPS data structure for debugging
        IO.puts("\nTPS data structure:")

        if tps_data["Last30DaysData"] do
          IO.puts("Last30DaysData keys: #{inspect(Map.keys(tps_data["Last30DaysData"]))}")

          if tps_data["Last30DaysData"]["DamageByPlayer"] do
            player_count = map_size(tps_data["Last30DaysData"]["DamageByPlayer"])
            IO.puts("DamageByPlayer has #{player_count} players")

            if player_count > 0 do
              sample_player = List.first(Map.keys(tps_data["Last30DaysData"]["DamageByPlayer"]))
              sample_data = tps_data["Last30DaysData"]["DamageByPlayer"][sample_player]
              IO.puts("Sample player data: #{inspect(sample_data)}")
            end
          end
        end

        if tps_data["Last12MonthsData"] do
          IO.puts("Last12MonthsData keys: #{inspect(Map.keys(tps_data["Last12MonthsData"]))}")
        end

      {:error, reason} ->
        IO.puts("Failed to fetch TPS data: #{inspect(reason)}")
    end
  end
end

# Automatically run the test
WandererNotifier.TPSChartTest.run()
