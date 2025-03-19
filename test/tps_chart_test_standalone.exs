defmodule WandererNotifier.TPSChartTest.Standalone do
  @moduledoc """
  Standalone test script for TPS chart generation.
  Only loads required modules without starting the full application.

  ## Usage

  Run with: `mix run test/tps_chart_test_standalone.exs`
  """

  def run do
    IO.puts("Starting standalone TPS chart test...")

    # Ensure minimum dependencies are loaded
    Application.ensure_all_started(:jason)
    Application.ensure_all_started(:httpoison)

    # Configure chart paths
    script_path = Path.expand("../priv/charts/simple_renderer.js", __DIR__)
    temp_dir = Path.expand("../priv/temp", __DIR__)
    charts_dir = Path.expand("../priv/static/images/charts", __DIR__)

    # Ensure directories exist
    File.mkdir_p!(temp_dir)
    File.mkdir_p!(charts_dir)

    IO.puts("Directories prepared:")
    IO.puts("- Script path: #{script_path}")
    IO.puts("- Temp dir: #{temp_dir}")
    IO.puts("- Charts dir: #{charts_dir}")

    # Create sample TPS data
    tps_data = create_sample_tps_data()

    IO.puts("\nCreated sample TPS data with structure:")

    if tps_data["Last30DaysData"] do
      IO.puts("Last30DaysData keys: #{inspect(Map.keys(tps_data["Last30DaysData"]))}")
    end

    # Direct generation - write data to file and call renderer
    timestamp = System.system_time(:second)
    data_file = Path.join(temp_dir, "tps_data_#{timestamp}.json")
    output_file = Path.join(charts_dir, "tps_chart_#{timestamp}.png")

    # Create chart config
    chart_config = %{
      "chart_type" => "damage_final_blows",
      "title" => "Test TPS Chart - Damage and Final Blows",
      "data" => tps_data
    }

    # Write data to file
    File.write!(data_file, Jason.encode!(chart_config))

    # Call the renderer
    IO.puts("\nCalling renderer directly...")
    cmd = "node #{script_path} #{data_file} #{output_file}"
    IO.puts("Executing: #{cmd}")

    case System.cmd("node", [script_path, data_file, output_file], stderr_to_stdout: true) do
      {output, 0} ->
        IO.puts("Chart generated successfully!")
        IO.puts("Output: #{output}")
        IO.puts("Chart saved to: #{output_file}")
        IO.puts("URL: file://#{output_file}")

      {error, code} ->
        IO.puts("Error generating chart (exit code: #{code})")
        IO.puts("Error: #{error}")

        # Check if output file exists anyway
        if File.exists?(output_file) do
          IO.puts("Output file exists despite error, size: #{File.stat!(output_file).size} bytes")
        else
          IO.puts("No output file was created")
        end
    end
  end

  # Creates a sample TPS data structure
  defp create_sample_tps_data do
    %{
      "Last30DaysData" => %{
        "DamageByPlayer" => %{
          "Player 1" => %{
            "DamageDone" => 15000,
            "FinalBlows" => 5
          },
          "Player 2" => %{
            "DamageDone" => 12000,
            "FinalBlows" => 3
          },
          "Player 3" => %{
            "DamageDone" => 8000,
            "FinalBlows" => 2
          }
        },
        "TotalKills" => 150,
        "TotalLosses" => 45
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
  end
end

# Run the test
WandererNotifier.TPSChartTest.Standalone.run()
