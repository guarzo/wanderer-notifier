#!/usr/bin/env elixir

# Script to verify the chart images generated
# Run with: elixir test/verify_charts.exs

IO.puts("Starting chart verification...")

# Get the project root directory
project_root = File.cwd!()
IO.puts("Project root: #{project_root}")

# Define the charts directory
charts_dir = Path.join([project_root, "priv", "static", "images", "charts"])
IO.puts("Charts directory: #{charts_dir}")

# Create a simple Node.js script to verify the chart image
verify_script_content = """
/**
 * Verify chart images to ensure they have actual content
 */
const fs = require('fs');
const { createCanvas, loadImage } = require('canvas');

async function verifyImage(imagePath) {
  console.log(`Verifying image: ${imagePath}`);

  try {
    // Load the image
    const image = await loadImage(imagePath);

    // Create canvas to analyze image
    const canvas = createCanvas(image.width, image.height);
    const ctx = canvas.getContext('2d');

    // Draw the image on canvas
    ctx.drawImage(image, 0, 0);

    // Get image data
    const imageData = ctx.getImageData(0, 0, image.width, image.height);
    const data = imageData.data;

    // Check if the image has non-background pixels
    // First, sample the background color (usually at the corners)
    const bgColorSamples = [
      getPixelColor(data, 0, 0, image.width),
      getPixelColor(data, image.width-1, 0, image.width),
      getPixelColor(data, 0, image.height-1, image.width),
      getPixelColor(data, image.width-1, image.height-1, image.width)
    ];

    // Find most common corner color as the background
    const bgColor = findMostCommonColor(bgColorSamples);
    console.log(`Detected background color: rgba(${bgColor.r},${bgColor.g},${bgColor.b},${bgColor.a})`);

    // Sample pixels in the middle of the image
    let nonBgPixels = 0;
    let totalPixels = 0;

    // Check a grid of sample points
    const sampleCount = 20;
    for (let x = 0; x < sampleCount; x++) {
      for (let y = 0; y < sampleCount; y++) {
        const sampleX = Math.floor((image.width / sampleCount) * x);
        const sampleY = Math.floor((image.height / sampleCount) * y);

        const color = getPixelColor(data, sampleX, sampleY, image.width);
        totalPixels++;

        // If this pixel is different from the background by more than a threshold
        if (colorDifference(color, bgColor) > 20) {
          nonBgPixels++;
        }
      }
    }

    // Calculate percentage of non-background pixels
    const nonBgPercentage = (nonBgPixels / totalPixels) * 100;
    console.log(`Non-background pixels: ${nonBgPixels}/${totalPixels} (${nonBgPercentage.toFixed(2)}%)`);

    // Check if the image has a reasonable amount of non-background pixels
    if (nonBgPercentage > 5) {
      console.log("✅ Image contains actual content (more than 5% non-background pixels)");
      return { success: true, message: "Image contains actual content" };
    } else {
      console.log("❌ Image might be blank or just background (less than 5% non-background pixels)");
      return {
        success: false,
        message: `Image appears to be mostly background (${nonBgPercentage.toFixed(2)}% non-background pixels)`
      };
    }
  } catch (error) {
    console.error(`Error verifying image: ${error.message}`);
    return { success: false, message: `Error: ${error.message}` };
  }
}

// Helper function to get pixel color at x,y
function getPixelColor(data, x, y, width) {
  const idx = (y * width + x) * 4;
  return {
    r: data[idx],
    g: data[idx + 1],
    b: data[idx + 2],
    a: data[idx + 3]
  };
}

// Helper function to calculate color difference
function colorDifference(color1, color2) {
  return Math.sqrt(
    Math.pow(color1.r - color2.r, 2) +
    Math.pow(color1.g - color2.g, 2) +
    Math.pow(color1.b - color2.b, 2)
  );
}

// Helper function to find most common color
function findMostCommonColor(colors) {
  // For simplicity, just return the first color
  // In a real implementation, you would count occurrences
  return colors[0];
}

// Main function
async function main() {
  // Get the image path from command line arguments
  const args = process.argv.slice(2);
  if (args.length === 0) {
    console.error('Usage: node verify_chart.js <image_path>');
    process.exit(1);
  }

  const imagePath = args[0];
  const result = await verifyImage(imagePath);

  // Output the result as JSON for easy parsing
  console.log(JSON.stringify(result));

  if (!result.success) {
    process.exit(1);
  }
}

// Run the main function
main().catch(error => {
  console.error('Unhandled error:', error);
  process.exit(1);
});
"""

# Write the verification script
verify_script_path = Path.join([project_root, "priv", "charts", "verify_chart.js"])
File.write!(verify_script_path, verify_script_content)
IO.puts("Created verification script at: #{verify_script_path}")

# Find recent chart images
{output, 0} =
  System.cmd("find", [charts_dir, "-name", "*.png", "-type", "f", "-mtime", "-1", "-print"])

recent_charts = output |> String.trim() |> String.split("\n") |> Enum.filter(&(&1 != ""))

if Enum.empty?(recent_charts) do
  IO.puts("No recent chart images found in the last 24 hours.")
else
  IO.puts("\nFound #{length(recent_charts)} recent chart images:")
  Enum.each(recent_charts, &IO.puts("  #{&1}"))

  IO.puts("\nVerifying chart images...")

  Enum.each(recent_charts, fn chart_path ->
    IO.puts("\n=== Verifying: #{Path.basename(chart_path)} ===")
    {output, status} = System.cmd("node", [verify_script_path, chart_path])

    IO.puts("Verification output:")
    IO.puts(output)

    if status == 0 do
      IO.puts("✅ Chart verified successfully")
    else
      IO.puts("❌ Chart verification failed")
    end
  end)
end

IO.puts("\nVerification completed")
