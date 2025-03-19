defmodule WandererNotifier.TPSChartDirectTest do
  @moduledoc """
  Direct test script for TPS chart generation.

  Run with: `mix run test/tps_chart_direct_test.exs`
  """

  alias WandererNotifier.CorpTools.ChartService

  def run do
    IO.puts("Starting direct TPS chart test...")

    # Initialize the chart service
    ChartService.init()

    # Create sample TPS data with the exact structure we need
    sample_data = %{
      "Last30DaysData" => %{
        "DamageByPlayer" => %{
          "Player 1" => %{"DamageDone" => 15000, "FinalBlows" => 5},
          "Player 2" => %{"DamageDone" => 12000, "FinalBlows" => 3},
          "Player 3" => %{"DamageDone" => 8000, "FinalBlows" => 2}
        }
      },
      "Last12MonthsData" => %{
        "KillsByMonth" => %{
          "2023-01" => 25,
          "2023-02" => 35,
          "2023-03" => 45
        },
        "KillsByShipType" => %{
          "Frigate" => 20,
          "Destroyer" => 15,
          "Cruiser" => 10
        }
      }
    }

    # Test each chart type
    test_chart("damage_final_blows", sample_data)
    test_chart("kills_by_ship_type", sample_data)
    test_chart("kills_by_month", sample_data)
  end

  defp test_chart(chart_type, data) do
    IO.puts("\n=== Testing #{chart_type} chart ===")

    case ChartService.generate_chart(chart_type, data) do
      {:ok, chart_path} ->
        IO.puts("✅ SUCCESS: Chart generated at #{chart_path}")
        IO.puts("Chart URL: file://#{chart_path}")

        # Check file size to ensure it's a valid chart
        case File.stat(chart_path) do
          {:ok, %{size: size}} ->
            IO.puts("Chart file size: #{size} bytes")

            if size > 1000 do
              IO.puts("Chart appears to be valid (size > 1KB)")
            else
              IO.puts(
                "⚠️ WARNING: Chart file is smaller than expected, might be empty or error page"
              )
            end

          {:error, reason} ->
            IO.puts("❌ ERROR: Failed to get file stats: #{inspect(reason)}")
        end

      {:error, reason} ->
        IO.puts("❌ ERROR: Failed to generate chart: #{inspect(reason)}")
    end
  end
end

# Run the test
WandererNotifier.TPSChartDirectTest.run()
