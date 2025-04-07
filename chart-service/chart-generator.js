import { createCanvas, registerFont } from 'canvas';
import { Chart } from 'chart.js/auto';
import ChartDataLabels from 'chartjs-plugin-datalabels';
import express from 'express';
import bodyParser from 'body-parser';
import fs from 'node:fs';
import path from 'node:path';

// Initialize fonts to ensure consistent rendering across environments
function initializeFonts() {
  console.log('Initializing fonts for chart service...');
  
  // Try to detect and register system fonts
  const fontDirectories = [
    '/usr/share/fonts',
    '/usr/local/share/fonts',
    '/fonts', // In case fonts are mounted in a custom directory
    path.join(process.env.HOME || process.env.USERPROFILE || '', '.fonts')
  ];

  // Check if a directory exists before trying to register fonts from it
  const existingDirectories = fontDirectories.filter(dir => {
    try {
      return fs.existsSync(dir);
    } catch (error) {
      console.warn(`Error checking font directory ${dir}:`, error.message);
      return false;
    }
  });

  if (existingDirectories.length === 0) {
    console.warn('No font directories found. Text rendering may be affected.');
  } else {
    console.log(`Found font directories: ${existingDirectories.join(', ')}`);
    
    // Register specific common fonts if available
    try {
      // Register DejaVu Sans - common in Linux environments
      registerFont('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf', { family: 'DejaVu Sans' });
      console.log('Registered DejaVu Sans font');
    } catch (error) {
      console.warn('Failed to register DejaVu Sans font:', error.message);
    }
    
    try {
      // Register Liberation Sans - another common Linux font
      registerFont('/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf', { family: 'Liberation Sans' });
      console.log('Registered Liberation Sans font');
    } catch (error) {
      console.warn('Failed to register Liberation Sans font:', error.message);
    }

    try {
      // Let's also try the first .ttf font we find in the first existing directory
      const firstDir = existingDirectories[0];
      const ttfFiles = searchForFonts(firstDir);
      
      if (ttfFiles.length > 0) {
        console.log(`Found ${ttfFiles.length} font files, registering the first one as a fallback`);
        registerFont(ttfFiles[0], { family: 'Fallback Font' });
        console.log(`Registered font: ${ttfFiles[0]}`);
      }
    } catch (error) {
      console.warn('Error during font search:', error.message);
    }
  }
}

// Recursively search for .ttf files in a directory (up to a certain depth)
function searchForFonts(directory, depth = 0, maxDepth = 2) {
  if (depth > maxDepth) return [];
  
  let results = [];
  
  try {
    const items = fs.readdirSync(directory);
    
    for (const item of items) {
      const fullPath = path.join(directory, item);
      
      try {
        const stat = fs.statSync(fullPath);
        
        if (stat.isDirectory()) {
          results = results.concat(searchForFonts(fullPath, depth + 1, maxDepth));
        } else if (item.endsWith('.ttf') || item.endsWith('.TTF')) {
          results.push(fullPath);
        }
      } catch (error) {
        console.warn(`Error accessing ${fullPath}:`, error.message);
      }
    }
  } catch (error) {
    console.warn(`Error reading directory ${directory}:`, error.message);
  }
  
  return results;
}

// Initialize fonts at startup
initializeFonts();

// Register required plugins
Chart.register(ChartDataLabels);

// Initialize Express app
const app = express();
app.use(bodyParser.json({ limit: '10mb' }));

// Add a health check endpoint
app.get('/health', (req, res) => {
  res.json({
    status: 'ok',
    service: 'chart-service',
    uptime: process.uptime(),
    timestamp: Date.now()
  });
});

// Configure chart dimensions and defaults
const WIDTH = 800;
const HEIGHT = 400;
const DISCORD_DARK_BG = 'rgb(47, 49, 54)';
const WHITE_TEXT = 'rgb(255, 255, 255)';

// Create a canvas for the chart
function createChartCanvas(width = WIDTH, height = HEIGHT) {
  return createCanvas(width, height);
}

// Helper function to create a fallback chart when no data is available
async function createNoDataChart(title, message = 'No data available for this chart') {
  const canvas = createChartCanvas();
  const ctx = canvas.getContext('2d');
  
  const configuration = {
    type: 'bar',
    data: {
      labels: [message],
      datasets: [{
        label: '',
        data: [0],
        backgroundColor: 'rgba(200, 200, 200, 0.2)',
        borderColor: 'rgba(200, 200, 200, 0.2)',
        borderWidth: 0
      }]
    },
    options: {
      plugins: {
        title: {
          display: true,
          text: title,
          color: WHITE_TEXT,
          font: {
            size: 18,
            family: "'DejaVu Sans', 'Liberation Sans', 'Fallback Font', sans-serif"
          }
        },
        legend: {
          display: false
        }
      },
      scales: {
        x: {
          display: false
        },
        y: {
          display: false
        }
      },
      backgroundColor: DISCORD_DARK_BG
    }
  };

  new Chart(ctx, configuration);
  return canvas.toBuffer('image/png');
}

// Generate chart from configuration
app.post('/generate', async (req, res) => {
  try {
    const { chart, width = WIDTH, height = HEIGHT, backgroundColor = DISCORD_DARK_BG } = req.body;
    
    if (!chart) {
      return res.status(400).json({ success: false, message: 'Chart configuration is required' });
    }

    // Create canvas with specified dimensions
    const canvas = createChartCanvas(width, height);
    const ctx = canvas.getContext('2d');

    // Fill background if specified
    if (backgroundColor) {
      ctx.fillStyle = backgroundColor;
      ctx.fillRect(0, 0, width, height);
    }

    // Ensure font family is specified in the chart options
    if (chart.options?.plugins) {
      // Ensure we have a plugins object
      if (!chart.options.plugins) {
        chart.options.plugins = {};
      }
      
      // Set global font defaults
      if (!chart.options.plugins.tooltip) {
        chart.options.plugins.tooltip = {};
      }
      if (!chart.options.plugins.title) {
        chart.options.plugins.title = {};
      }
      if (!chart.options.plugins.legend) {
        chart.options.plugins.legend = {};
      }
      
      // Set font family for tooltips
      if (!chart.options.plugins.tooltip.titleFont) {
        chart.options.plugins.tooltip.titleFont = { family: "'DejaVu Sans', 'Liberation Sans', 'Fallback Font', sans-serif" };
      }
      if (!chart.options.plugins.tooltip.bodyFont) {
        chart.options.plugins.tooltip.bodyFont = { family: "'DejaVu Sans', 'Liberation Sans', 'Fallback Font', sans-serif" };
      }
      
      // Set font family for title
      if (!chart.options.plugins.title.font) {
        chart.options.plugins.title.font = { family: "'DejaVu Sans', 'Liberation Sans', 'Fallback Font', sans-serif" };
      }
      
      // Set font family for legend
      if (!chart.options.plugins.legend.labels && chart.options.plugins.legend.display !== false) {
        chart.options.plugins.legend.labels = { font: { family: "'DejaVu Sans', 'Liberation Sans', 'Fallback Font', sans-serif" } };
      }
    }
    
    // Set global defaults for scales
    if (chart.options?.scales) {
      const scaleTypes = ['x', 'y', 'r', 'xAxes', 'yAxes'];
      
      for (const scaleType of scaleTypes) {
        if (chart.options.scales[scaleType]) {
          if (Array.isArray(chart.options.scales[scaleType])) {
            // Handle arrays (Chart.js v2.x format)
            chart.options.scales[scaleType].forEach(axis => {
              if (!axis.ticks) axis.ticks = {};
              if (!axis.ticks.font) axis.ticks.font = { family: "'DejaVu Sans', 'Liberation Sans', 'Fallback Font', sans-serif" };
            });
          } else {
            // Handle objects (Chart.js v3.x format)
            if (!chart.options.scales[scaleType].ticks) chart.options.scales[scaleType].ticks = {};
            if (!chart.options.scales[scaleType].ticks.font) {
              chart.options.scales[scaleType].ticks.font = { family: "'DejaVu Sans', 'Liberation Sans', 'Fallback Font', sans-serif" };
            }
          }
        }
      }
    }
    // Create the chart
    new Chart(ctx, chart);
    
    // Convert to buffer and base64
    const buffer = canvas.toBuffer('image/png');
    const base64Image = buffer.toString('base64');
    
    res.json({
      success: true,
      imageData: base64Image,
      contentType: 'image/png'
    });
  } catch (error) {
    console.error('Error generating chart:', error);
    res.status(500).json({ 
      success: false, 
      message: 'Error generating chart',
      error: error.message
    });
  }
});

// Generate a "no data" chart
app.post('/generate-no-data', async (req, res) => {
  try {
    const { title, message } = req.body;
    
    if (!title) {
      return res.status(400).json({ success: false, message: 'Chart title is required' });
    }

    const buffer = await createNoDataChart(title, message || 'No data available for this chart');
    const base64Image = buffer.toString('base64');
    
    res.json({
      success: true,
      imageData: base64Image,
      contentType: 'image/png'
    });
  } catch (error) {
    console.error('Error generating no-data chart:', error);
    res.status(500).json({ 
      success: false, 
      message: 'Error generating no-data chart',
      error: error.message
    });
  }
});

// Save chart to file and return the file path
app.post('/save', async (req, res) => {
  try {
    const { chart, fileName, width = WIDTH, height = HEIGHT, backgroundColor = DISCORD_DARK_BG } = req.body;
    
    if (!chart || !fileName) {
      return res.status(400).json({ 
        success: false, 
        message: 'Chart configuration and fileName are required' 
      });
    }

    // Create canvas with specified dimensions
    const canvas = createChartCanvas(width, height);
    const ctx = canvas.getContext('2d');

    // Fill background if specified
    if (backgroundColor) {
      ctx.fillStyle = backgroundColor;
      ctx.fillRect(0, 0, width, height);
    }
    
    // Ensure font family is specified in the chart options (same as in /generate endpoint)
    if (chart.options?.plugins) {
      // Ensure we have a plugins object
      if (!chart.options.plugins) {
        chart.options.plugins = {};
      }
      
      // Set global font defaults
      if (!chart.options.plugins.tooltip) {
        chart.options.plugins.tooltip = {};
      }
      if (!chart.options.plugins.title) {
        chart.options.plugins.title = {};
      }
      if (!chart.options.plugins.legend) {
        chart.options.plugins.legend = {};
      }
      
      // Set font family for tooltips
      if (!chart.options.plugins.tooltip.titleFont) {
        chart.options.plugins.tooltip.titleFont = { family: "'DejaVu Sans', 'Liberation Sans', 'Fallback Font', sans-serif" };
      }
      if (!chart.options.plugins.tooltip.bodyFont) {
        chart.options.plugins.tooltip.bodyFont = { family: "'DejaVu Sans', 'Liberation Sans', 'Fallback Font', sans-serif" };
      }
      
      // Set font family for title
      if (!chart.options.plugins.title.font) {
        chart.options.plugins.title.font = { family: "'DejaVu Sans', 'Liberation Sans', 'Fallback Font', sans-serif" };
      }
      
      // Set font family for legend
      if (!chart.options.plugins.legend.labels && chart.options.plugins.legend.display !== false) {
        chart.options.plugins.legend.labels = { font: { family: "'DejaVu Sans', 'Liberation Sans', 'Fallback Font', sans-serif" } };
      }
    }
    
    // Set global defaults for scales
    if (chart.options?.scales) {
      const scaleTypes = ['x', 'y', 'r', 'xAxes', 'yAxes'];
      
      for (const scaleType of scaleTypes) {
        if (chart.options.scales[scaleType]) {
          if (Array.isArray(chart.options.scales[scaleType])) {
            // Handle arrays (Chart.js v2.x format)
            chart.options.scales[scaleType].forEach(axis => {
              if (!axis.ticks) axis.ticks = {};
              if (!axis.ticks.font) axis.ticks.font = { family: "'DejaVu Sans', 'Liberation Sans', 'Fallback Font', sans-serif" };
            });
          } else {
            // Handle objects (Chart.js v3.x format)
            if (!chart.options.scales[scaleType].ticks) chart.options.scales[scaleType].ticks = {};
            if (!chart.options.scales[scaleType].ticks.font) {
              chart.options.scales[scaleType].ticks.font = { family: "'DejaVu Sans', 'Liberation Sans', 'Fallback Font', sans-serif" };
            }
          }
        }
      }
    }

    // Create the chart
    new Chart(ctx, chart);
    
    // Create output directory if it doesn't exist
    const outputDir = path.resolve('chart-output');
    if (!fs.existsSync(outputDir)) {
      fs.mkdirSync(outputDir, { recursive: true });
    }
    
    // Save chart to file
    const filePath = path.join(outputDir, fileName);
    const buffer = canvas.toBuffer('image/png');
    fs.writeFileSync(filePath, buffer);
    
    res.json({
      success: true,
      filePath: filePath,
      fileName: fileName
    });
  } catch (error) {
    console.error('Error saving chart:', error);
    res.status(500).json({ 
      success: false, 
      message: 'Error saving chart',
      error: error.message
    });
  }
});

// Start the server
const PORT = process.env.WANDERER_CHART_SERVICE_PORT || process.env.CHART_SERVICE_PORT || 3001;
console.log(`Starting chart service on port ${PORT}`);
console.log(`Environment variables: WANDERER_CHART_SERVICE_PORT=${process.env.WANDERER_CHART_SERVICE_PORT || 'not set'}, CHART_SERVICE_PORT=${process.env.CHART_SERVICE_PORT || 'not set'}`);

app.listen(PORT, () => {
  console.log(`Chart service running on port ${PORT}`);
  console.log(`Process started with PID: ${process.pid}`);
  
  // Setup graceful shutdown
  process.on('SIGTERM', () => {
    console.log('SIGTERM signal received: closing chart service');
    process.exit(0);
  });
  
  process.on('SIGINT', () => {
    console.log('SIGINT signal received: closing chart service');
    process.exit(0);
  });
});