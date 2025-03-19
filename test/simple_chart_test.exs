defmodule WandererNotifier.SimpleChartTest do
  @moduledoc """
  Simplified test script for chart generation that doesn't depend on the full application.

  Run with: mix run test/simple_chart_test.exs
  """

  require Logger

  def run do
    IO.puts("Starting simplified chart test...")

    # Initialize required libraries only
    Application.ensure_all_started(:hackney)
    Application.ensure_all_started(:jason)

    # Define paths
    priv_dir = :code.priv_dir(:wanderer_notifier)
    script_path = Path.join(priv_dir, "charts/simple_renderer.js")
    temp_dir = Path.join(priv_dir, "temp")
    charts_dir = Path.join(priv_dir, "static/images/charts")

    # Ensure directories exist
    File.mkdir_p!(temp_dir)
    File.mkdir_p!(charts_dir)

    IO.puts("Chart renderer script path: #{script_path}")

    # Ensure Node.js dependencies are installed
    charts_dir_path = Path.join(priv_dir, "charts")
    node_modules_path = Path.join(charts_dir_path, "node_modules")

    if !File.exists?(node_modules_path) do
      IO.puts("Installing Node.js dependencies for chart generation...")

      case System.cmd("npm", ["install"], cd: charts_dir_path) do
        {output, 0} ->
          IO.puts("Successfully installed Node.js dependencies")

        {output, status} ->
          IO.puts("Failed to install Node.js dependencies. Status: #{status}")
          IO.puts("Output: #{output}")
      end
    else
      IO.puts("Node.js dependencies already installed")
    end

    # Create sample data for damage_final_blows chart
    sample_data = %{
      "TimeFrames" => %{
        "0" => %{
          "Name" => "MTD",
          "Charts" => %{
            "0" => %{
              "ID" => "damage_final_blows",
              "Name" => "Damage and Final Blows",
              "Type" => "bar",
              "Data" =>
                Jason.encode!([
                  %{"Name" => "Player1", "DamageDone" => 150_000, "FinalBlows" => 12},
                  %{"Name" => "Player2", "DamageDone" => 120_000, "FinalBlows" => 10},
                  %{"Name" => "Player3", "DamageDone" => 100_000, "FinalBlows" => 8}
                ])
            }
          }
        }
      }
    }

    # Write data to temp file
    timestamp = DateTime.utc_now() |> DateTime.to_unix()
    data_file = Path.join(temp_dir, "chart_data_#{timestamp}.json")
    output_file = Path.join(charts_dir, "test_chart_#{timestamp}.png")

    # Encode and write data to temp file
    json_data = Jason.encode!(sample_data)
    IO.puts("Writing data to: #{data_file}")
    File.write!(data_file, json_data)

    # Call Node.js script directly to generate chart
    IO.puts("Calling Node.js script to generate chart...")
    command = "node #{script_path} damage_final_blows #{data_file} #{output_file}"
    IO.puts("Command: #{command}")

    result = System.cmd("node", [script_path, "damage_final_blows", data_file, output_file])

    case result do
      {output, 0} ->
        IO.puts("Command successful!")
        IO.puts("Chart generated successfully at: #{output_file}")
        IO.puts("Chart URL: file://#{output_file}")

        # Check if file exists
        if File.exists?(output_file) do
          file_size = File.stat!(output_file).size
          IO.puts("Output file exists and has size: #{file_size} bytes")

          if file_size > 0 do
            IO.puts("Chart generated successfully!")
          else
            IO.puts("WARNING: Output file exists but is empty")
          end
        else
          IO.puts("ERROR: Output file doesn't exist!")
        end

      {output, status} ->
        IO.puts("Command failed with status #{status}")
        IO.puts("Output: #{output}")
    end

    # Clean up temp file
    File.rm(data_file)

    IO.puts("Test completed")
  end
end

# Run the test
WandererNotifier.SimpleChartTest.run()
