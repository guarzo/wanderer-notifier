defmodule WandererNotifier.ChartTest do
  @moduledoc """
  Test script for manually testing chart generation through the ChartService.

  ## Usage

  Run with: `mix run test/chart_test.exs`

  This script:
  1. Initializes the ChartService
  2. Creates sample chart data
  3. Calls ChartService.generate_chart/2
  4. Reports the results

  ## Troubleshooting Tips

  - If there are rendering issues, try the direct test in direct_chart_test.exs
  - Check chart_rendering.md for common issues and solutions
  - To test different chart types, modify the 'damage_final_blows' parameter
  """

  alias WandererNotifier.CorpTools.ChartService
  alias WandererNotifier.CorpTools.ChartConfig
  alias WandererNotifier.CorpTools.ChartTypes

  def run do
    IO.puts("Initializing chart service...")
    # Make sure Jason is loaded
    Application.ensure_all_started(:jason)

    # Initialize chart service directly
    ChartService.init()

    # Create test data
    test_data = [
      %{"Name" => "Player 1", "DamageDone" => 15000, "FinalBlows" => 5},
      %{"Name" => "Player 2", "DamageDone" => 12000, "FinalBlows" => 3},
      %{"Name" => "Player 3", "DamageDone" => 8000, "FinalBlows" => 2}
    ]

    # Create a chart config
    IO.puts("Creating chart configuration...")

    case ChartConfig.new(%{
           type: ChartTypes.damage_final_blows(),
           title: "Test Chart - Damage and Final Blows",
           data: test_data
         }) do
      {:ok, config} ->
        # Generate the chart using the new API
        IO.puts("Generating chart using ChartConfig...")

        case ChartService.generate_chart(config) do
          {:ok, chart_path} ->
            IO.puts("Chart generated successfully at: #{chart_path}")
            IO.puts("Chart URL: file://#{chart_path}")
            IO.puts("Would send chart to Discord: #{chart_path}")

          {:error, reason} ->
            IO.puts("Failed to generate chart: #{inspect(reason)}")
        end

        # Also test the legacy interface for compatibility
        IO.puts("\nTesting legacy interface...")
        # Sample data for testing legacy interface
        sample_data = %{
          "TimeFrames" => %{
            "Current" => %{
              "Charts" => %{
                "damage_final_blows" => %{
                  "id" => "damage_final_blows",
                  "name" => "Damage and Final Blows",
                  "type" => "bar",
                  "Data" => Jason.encode!(test_data)
                }
              }
            }
          }
        }

        case ChartService.generate_chart("damage_final_blows", sample_data) do
          {:ok, chart_path} ->
            IO.puts("Legacy chart generated successfully at: #{chart_path}")
            IO.puts("Legacy chart URL: file://#{chart_path}")

          {:error, reason} ->
            IO.puts("Failed to generate legacy chart: #{inspect(reason)}")
        end

      {:error, reason} ->
        IO.puts("Failed to create chart configuration: #{inspect(reason)}")
    end
  end
end

# Automatically run the test
WandererNotifier.ChartTest.run()
