#!/usr/bin/env elixir

# Debug script for chart generation that prints detailed data structure information
# Run with: elixir test/debug_chart_test.exs

# Required dependencies
Mix.install([
  {:jason, "~> 1.3"}
])

IO.puts("Starting chart debugging...")

# Get the project root directory
project_root = File.cwd!()
IO.puts("Project root: #{project_root}")

# Define paths relative to project root
priv_dir = Path.join(project_root, "priv")
script_path = Path.join(priv_dir, "charts/debug_renderer.js")
temp_dir = Path.join(priv_dir, "temp")
charts_dir = Path.join(priv_dir, "static/images/charts")

# Ensure directories exist
File.mkdir_p!(temp_dir)
File.mkdir_p!(charts_dir)

# First, create a debug renderer script that will help us diagnose the issue
debug_renderer_content = """
/**
 * Debug renderer for chart generation
 */
const fs = require('fs');
const path = require('path');
const { createCanvas } = require('canvas');
const Chart = require('chart.js/auto');

// Read the arguments
const args = process.argv.slice(2);
if (args.length < 2) {
  console.error('Usage: node debug_renderer.js <data_file> <output_file>');
  process.exit(1);
}

const dataFilePath = args[0];
const outputPath = args[1];

// Read and parse the data file
console.log(`Reading data from ${dataFilePath}`);
const rawData = fs.readFileSync(dataFilePath, 'utf8');
console.log('Raw data (first 200 chars):', rawData.substring(0, 200), '...');

try {
  // Parse the JSON data
  const data = JSON.parse(rawData);

  // Log the data structure
  console.log('\\nData structure:');
  console.log('Object keys:', Object.keys(data));

  if (data.TimeFrames) {
    console.log('\\nTimeFrames keys:', Object.keys(data.TimeFrames));

    const firstTimeframe = data.TimeFrames[Object.keys(data.TimeFrames)[0]];
    if (firstTimeframe) {
      console.log('First timeframe keys:', Object.keys(firstTimeframe));

      if (firstTimeframe.Charts) {
        console.log('Charts keys:', Object.keys(firstTimeframe.Charts));

        const firstChart = firstTimeframe.Charts[Object.keys(firstTimeframe.Charts)[0]];
        if (firstChart) {
          console.log('First chart:', JSON.stringify(firstChart, null, 2));

          if (firstChart.Data) {
            try {
              const chartData = JSON.parse(firstChart.Data);
              console.log('\\nChart data (parsed, first 2 items):',
                JSON.stringify(chartData.slice(0, 2), null, 2));
            } catch (e) {
              console.log('Error parsing chart Data:', e.message);
              console.log('Raw chart Data:', firstChart.Data);
            }
          }
        }
      }
    }
  }

  // Create a simple test chart
  console.log('\\nGenerating test chart...');
  const width = 800;
  const height = 400;
  const canvas = createCanvas(width, height);
  const ctx = canvas.getContext('2d');

  // Set background
  ctx.fillStyle = '#2F3136'; // Discord dark theme
  ctx.fillRect(0, 0, width, height);

  // Add some text to show it's working
  ctx.font = '30px Arial';
  ctx.fillStyle = '#FFFFFF';
  ctx.textAlign = 'center';
  ctx.fillText('Debug Chart', width / 2, 50);
  ctx.font = '16px Arial';
  ctx.fillText('This is a test debug chart', width / 2, 100);

  // Draw a simple bar chart
  const testData = [12, 19, 3, 5, 2, 3];
  const barWidth = width / (testData.length * 2);
  const maxValue = Math.max(...testData);

  testData.forEach((value, i) => {
    const x = i * (barWidth * 2) + barWidth / 2;
    const barHeight = (value / maxValue) * (height - 150);

    ctx.fillStyle = 'rgba(255, 99, 132, 0.7)';
    ctx.fillRect(x, height - 50 - barHeight, barWidth, barHeight);

    ctx.fillStyle = '#FFFFFF';
    ctx.textAlign = 'center';
    ctx.fillText(value.toString(), x + barWidth / 2, height - 55 - barHeight);
  });

  // Save the canvas to a PNG file
  const buffer = canvas.toBuffer('image/png');
  fs.writeFileSync(outputPath, buffer);
  console.log(`Debug chart saved to: ${outputPath}`);

} catch (error) {
  console.error('Error processing data:', error.message);
  console.error(error.stack);
}
"""

# Write the debug renderer script
debug_renderer_path = Path.join(priv_dir, "charts/debug_renderer.js")
File.write!(debug_renderer_path, debug_renderer_content)
IO.puts("Created debug renderer at: #{debug_renderer_path}")

# Create sample data for damage_final_blows chart
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

# Write data to temp file
timestamp = DateTime.utc_now() |> DateTime.to_unix()
data_file = Path.join(temp_dir, "debug_chart_data_#{timestamp}.json")
output_file = Path.join(charts_dir, "debug_chart_#{timestamp}.png")

# Encode and write data to temp file
json_data = Jason.encode!(damage_final_blows_data)
IO.puts("\nData structure being sent to renderer:")
IO.puts(Jason.encode!(damage_final_blows_data, pretty: true))
IO.puts("\nWriting data to: #{data_file}")
File.write!(data_file, json_data)

# Call the debug renderer directly
IO.puts("\nCalling debug renderer script...")
command = "node #{debug_renderer_path} #{data_file} #{output_file}"
IO.puts("Command: #{command}")

result = System.cmd("node", [debug_renderer_path, data_file, output_file])

case result do
  {output, 0} ->
    IO.puts("Command successful!")
    IO.puts("Debug output from renderer:")
    IO.puts(output)
    IO.puts("\nDebug chart generated at: #{output_file}")
    IO.puts("Chart URL: file://#{output_file}")

    # Check if file exists
    if File.exists?(output_file) do
      file_size = File.stat!(output_file).size
      IO.puts("Output file exists and has size: #{file_size} bytes")
    else
      IO.puts("ERROR: Output file doesn't exist!")
    end

  {output, status} ->
    IO.puts("Command failed with status #{status}")
    IO.puts("Output: #{output}")
end

# Clean up temp file
File.rm(data_file)

IO.puts("\nDebugging completed")
