#!/usr/bin/env elixir

# This script is designed to be run standalone without starting the full application
# Run it with: elixir test/standalone_chart_test.exs

# Required dependencies
Mix.install([
  {:jason, "~> 1.3"}
])

IO.puts("Starting standalone chart test...")

# Get the project root directory
project_root = File.cwd!()
IO.puts("Project root: #{project_root}")

# Define paths relative to project root
priv_dir = Path.join(project_root, "priv")
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
    {_output, 0} ->
      IO.puts("Successfully installed Node.js dependencies")

    {output, status} ->
      IO.puts("Failed to install Node.js dependencies. Status: #{status}")
      IO.puts("Output: #{output}")
  end
else
  IO.puts("Node.js dependencies already installed")
end

# Function to test chart generation
defmodule ChartTester do
  def test_chart(chart_type, sample_data, priv_dir, script_path) do
    IO.puts("\n=== Testing chart type: #{chart_type} ===")

    # Define directories
    temp_dir = Path.join(priv_dir, "temp")
    charts_dir = Path.join(priv_dir, "static/images/charts")

    # Write data to temp file
    timestamp = DateTime.utc_now() |> DateTime.to_unix()
    data_file = Path.join(temp_dir, "chart_data_#{chart_type}_#{timestamp}.json")
    output_file = Path.join(charts_dir, "test_chart_#{chart_type}_#{timestamp}.png")

    # Encode and write data to temp file
    json_data = Jason.encode!(sample_data)
    IO.puts("Writing data to: #{data_file}")
    File.write!(data_file, json_data)

    # Call Node.js script directly to generate chart
    IO.puts("Calling Node.js script to generate chart...")
    command = "node #{script_path} #{chart_type} #{data_file} #{output_file}"
    IO.puts("Command: #{command}")

    result = System.cmd("node", [script_path, chart_type, data_file, output_file])

    case result do
      {_output, 0} ->
        IO.puts("Command successful!")
        IO.puts("Chart generated successfully at: #{output_file}")
        IO.puts("Chart URL: file://#{output_file}")

        # Check if file exists
        if File.exists?(output_file) do
          file_size = File.stat!(output_file).size
          IO.puts("Output file exists and has size: #{file_size} bytes")

          if file_size > 0 do
            IO.puts("Chart generated successfully!")
            # Clean up temp file
            File.rm(data_file)
            {:ok, output_file}
          else
            IO.puts("WARNING: Output file exists but is empty")
            File.rm(data_file)
            {:error, :empty_file}
          end
        else
          IO.puts("ERROR: Output file doesn't exist!")
          File.rm(data_file)
          {:error, :file_not_found}
        end

      {output, status} ->
        IO.puts("Command failed with status #{status}")
        IO.puts("Output: #{output}")
        File.rm(data_file)
        {:error, status}
    end
  end
end

# === Test damage_final_blows chart ===
damage_final_blows_data = %{
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

ChartTester.test_chart("damage_final_blows", damage_final_blows_data, priv_dir, script_path)

# === Test combined_losses chart ===
combined_losses_data = %{
  "TimeFrames" => %{
    "0" => %{
      "Name" => "MTD",
      "Charts" => %{
        "0" => %{
          "ID" => "combined_losses",
          "Name" => "Combined Losses",
          "Type" => "bar",
          "Data" =>
            Jason.encode!([
              %{
                "character_name" => "Player1",
                "ship_losses" => 5,
                "pod_losses" => 3,
                "total_losses" => 8
              },
              %{
                "character_name" => "Player2",
                "ship_losses" => 4,
                "pod_losses" => 2,
                "total_losses" => 6
              },
              %{
                "character_name" => "Player3",
                "ship_losses" => 3,
                "pod_losses" => 2,
                "total_losses" => 5
              },
              %{
                "character_name" => "Player4",
                "ship_losses" => 2,
                "pod_losses" => 1,
                "total_losses" => 3
              }
            ])
        }
      }
    }
  }
}

ChartTester.test_chart("combined_losses", combined_losses_data, priv_dir, script_path)

IO.puts("\nAll tests completed")
