# Chart.js Node Service for WandererNotifier

This service provides server-side chart generation using Chart.js and Node.js. It replaces the external dependency on QuickChart.io with a local service that can generate chart images directly.

## Features

- Generate chart images using Chart.js
- Support for all standard Chart.js chart types and options
- Optimized for Discord's dark theme
- Fallback to QuickChart.io if service is unavailable

## Installation

The chart service uses dependencies from the main renderer package.json. To install:

```
cd renderer
npm install
```

## Running the Service

To start the chart service:

```
cd renderer
npm run chart-service
```

The service runs on port 3001 by default. You can change this by setting the `CHART_SERVICE_PORT` environment variable.

## API Endpoints

### Generate Chart

`POST /generate`

Generates a chart image from a configuration.

Request body:
```json
{
  "chart": {
    "type": "bar",
    "data": {
      "labels": ["A", "B", "C"],
      "datasets": [{"label": "Data", "data": [1, 2, 3]}]
    },
    "options": {...}
  },
  "width": 800,
  "height": 400,
  "backgroundColor": "rgb(47, 49, 54)"
}
```

### Generate No-Data Chart

`POST /generate-no-data`

Generates a placeholder chart when no data is available.

Request body:
```json
{
  "title": "Chart Title",
  "message": "No data available for this chart"
}
```

### Save Chart to File

`POST /save`

Generates a chart and saves it to disk.

Request body:
```json
{
  "chart": {...},
  "fileName": "chart.png",
  "width": 800,
  "height": 400,
  "backgroundColor": "rgb(47, 49, 54)"
}
```

## Integration with Elixir

The service is integrated with the Elixir application through:

1. `WandererNotifier.ChartService.ChartServiceManager` - Manages the lifecycle of the Node.js chart service, including:
   - Starting the service automatically when the Elixir application starts
   - Monitoring the service's health
   - Restarting the service if it crashes or becomes unresponsive
   - Providing a health check endpoint

2. `WandererNotifier.ChartService.NodeChartAdapter` - Communicates with the service via HTTP:
   - Translates between Elixir chart configurations and the Node.js service format
   - Handles error cases with automatic fallbacks 
   - Supports multiple output formats (binary data, file output)

### Health Check Endpoint

`GET /health`

Returns the service status information:

```json
{
  "status": "ok",
  "service": "chart-service",
  "uptime": 123.456,
  "timestamp": 1647331234567
}
```

This endpoint is used by the ChartServiceManager to monitor the service health.