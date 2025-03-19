defmodule WandererNotifier.DirectChartTest do
  @moduledoc """
  Direct test for chart generation without using ChartService.
  This test bypasses the service layer to directly test the Node.js renderer.

  ## Usage

  Run with: `mix run test/direct_chart_test.exs`

  This script:
  1. Creates sample chart data in JSON format
  2. Writes it to a temporary file
  3. Calls the Node.js renderer directly
  4. Reports the results and output path

  ## Benefits

  - Bypasses the Elixir service layer for simplified debugging
  - Directly tests the Node.js renderer
  - Shows detailed renderer output
  - Useful for font and rendering issues

  ## Troubleshooting

  If rendering issues persist:
  1. Check the actual error output for specific Node.js errors
  2. Inspect the generated JSON data file
  3. Try modifying the chart data structure
  4. See chart_rendering.md for common issues and solutions
  """

  def run do
    IO.puts("Starting direct chart renderer test...")

    # Ensure temporary directory exists
    temp_dir =
      Path.join([File.cwd!(), "_build", "dev", "lib", "wanderer_notifier", "priv", "temp"])

    File.mkdir_p!(temp_dir)

    # Create output directory
    charts_dir =
      Path.join([
        File.cwd!(),
        "_build",
        "dev",
        "lib",
        "wanderer_notifier",
        "priv",
        "static",
        "images",
        "charts"
      ])

    File.mkdir_p!(charts_dir)

    # Create test data
    test_data = [
      %{"Name" => "Player 1", "DamageDone" => 15000, "FinalBlows" => 5},
      %{"Name" => "Player 2", "DamageDone" => 12000, "FinalBlows" => 3},
      %{"Name" => "Player 3", "DamageDone" => 8000, "FinalBlows" => 2}
    ]

    # Generate unique ID for this test
    timestamp = System.system_time(:second)

    # Prepare chart data JSON file
    data_file = Path.join(temp_dir, "chart_data_#{timestamp}.json")

    chart_config = %{
      chart_type: "damage_final_blows",
      title: "Test Chart - Damage and Final Blows",
      data: test_data
    }

    # Write data to file
    File.write!(data_file, Jason.encode!(chart_config))

    # Define output file
    output_file = Path.join(charts_dir, "direct_test_chart_#{timestamp}.png")

    # Build renderer path
    node_renderer = Path.join([File.cwd!(), "priv", "charts", "simple_renderer.js"])

    # Execute node command directly
    cmd = "node #{node_renderer} #{data_file} #{output_file}"
    IO.puts("Executing: #{cmd}")

    case System.cmd("node", [node_renderer, data_file, output_file], stderr_to_stdout: true) do
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
end

# Run the test
WandererNotifier.DirectChartTest.run()
