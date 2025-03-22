# ChartService Architecture

## Overview
The ChartService is a unified system for chart generation and delivery in the WandererNotifier application. It provides a consistent, standardized interface for all chart-related functionality, replacing the previous fragmented approach with multiple adapters handling both data preparation and rendering.

## Components

### ChartService
The central module that provides the core functionality for generating chart URLs and sending charts to Discord. It handles all chart rendering and delivery logic, delegating data preparation to specialized adapters.

```elixir
# Generate a chart URL
{:ok, url} = ChartService.generate_chart_url(chart_config)

# Send a chart to Discord
ChartService.send_chart_to_discord(url, "My Chart", "Chart description")
```

### ChartConfig
A struct that standardizes chart configuration with validation. It ensures that all chart configurations are properly structured before being encoded to JSON.

```elixir
# Create a new chart configuration
{:ok, config} = ChartConfig.new(
  ChartTypes.bar(),
  chart_data,
  "Chart Title",
  options
)
```

### ChartTypes
Constants for all chart types used throughout the application, ensuring consistency and preventing duplication.

```elixir
# Standard chart types
ChartTypes.bar()       # "bar"
ChartTypes.line()      # "line"
ChartTypes.doughnut()  # "doughnut"

# Feature-specific chart types
ChartTypes.kills_by_ship_type()  # "kills_by_ship_type"
ChartTypes.activity_summary()    # "activity_summary"
```

### Errors
Structured error types for different failure scenarios, improving error handling and reporting.

```elixir
# Convert an error tuple to a structured exception
exception = Errors.to_exception({:error, reason}, Errors.DataError)

# Format an error response for API endpoints
error_response = Errors.format_response({:error, reason})
```

## Adapters
Adapters are responsible only for data preparation, extracting and transforming domain-specific data into chart-ready formats. They use the ChartService for rendering and delivery.


### ActivityChartAdapter
Prepares data for character activity charts.

```elixir
# Generate a character activity summary chart
ActivityChartAdapter.generate_activity_summary_chart(activity_data)

# Send all activity charts to Discord
ActivityChartAdapter.send_all_charts_to_discord(activity_data)
```

## Workflow

1. An adapter prepares data for a specific chart type
2. The data is converted into a ChartConfig struct with validation
3. ChartService generates a chart URL from the configuration
4. The chart is sent to Discord as an embed (optional)

## Benefits

- **Clear Separation of Concerns**: Data preparation is separated from rendering
- **Standardized Interface**: Consistent approach for all chart types
- **Enhanced Reliability**: Better error handling and fallback mechanisms
- **Simplified Maintenance**: Common code centralized in the ChartService
- **Type Safety**: Improved validation and type specifications

## Future Considerations

- Alternative chart libraries beyond QuickChart
- Server-side rendering for complex charts
- Interactive charts for web dashboards 