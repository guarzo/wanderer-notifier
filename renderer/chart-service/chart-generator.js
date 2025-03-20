import { createCanvas } from 'canvas';
import { Chart } from 'chart.js/auto';
import ChartDataLabels from 'chartjs-plugin-datalabels';
import express from 'express';
import bodyParser from 'body-parser';
import fs from 'fs';
import path from 'path';

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
            size: 18
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
const PORT = process.env.CHART_SERVICE_PORT || 3001;
app.listen(PORT, () => {
  console.log(`Chart service running on port ${PORT}`);
});