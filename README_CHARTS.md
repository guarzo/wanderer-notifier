# EVE Corp Tools Chart Integration

This document explains how to use the EVE Corp Tools chart integration with Discord notifications.

## Overview

The chart integration allows you to generate and send beautiful charts to Discord based on TPS (Time, Pilots, Ships) data from the EVE Corp Tools API. These charts provide visual insights into your corporation's or alliance's performance in EVE Online.

## Configuration

### Environment Variables

The following environment variables are used to configure the chart integration:

- `CORP_TOOLS_API_URL`: The URL of the EVE Corp Tools Service API (required)
- `CORP_TOOLS_API_TOKEN`: The API token for authenticating with the EVE Corp Tools Service API (required)
- `CHART_SCHEDULER_INTERVAL_MS`: The interval in milliseconds between automatic chart updates (optional, defaults to 24 hours)

Example:

```
CORP_TOOLS_API_URL=http://your-server-address/service-api
CORP_TOOLS_API_TOKEN=your-api-token
CHART_SCHEDULER_INTERVAL_MS=86400000  # 24 hours in milliseconds
```

## Available Charts

The following charts are currently available:

1. **Damage and Final Blows**: Shows the top 20 characters by damage done and final blows
2. **Combined Losses**: Shows the top 10 characters by losses value and count
3. **Kill Activity Over Time**: Shows the kill activity trend over time

## Usage

### Automatic Chart Updates

Charts are automatically sent to Discord at the interval specified by `CHART_SCHEDULER_INTERVAL_MS`. By default, this is set to 24 hours.

### Manual Chart Generation

You can manually generate and send charts to Discord using the IEx console:

```elixir
# Send all charts
WandererNotifier.CorpTools.ChartScheduler.send_all_charts()

# Or use the JS chart adapter directly for specific charts
WandererNotifier.CorpTools.JSChartAdapter.send_chart_to_discord(
  :damage_final_blows,
  "Damage and Final Blows Analysis",
  "Top 20 characters by damage done and final blows"
)
```

### Debugging TPS Data

If you're having issues with the charts or want to understand the structure of the TPS data, you can use the TPS Data Inspector:

```elixir
# Inspect the TPS data structure
WandererNotifier.CorpTools.TPSDataInspector.inspect_tps_data()

# Deep inspect the TPS data structure (with a specified depth)
WandererNotifier.CorpTools.TPSDataInspector.deep_inspect_tps_data(3)
```

## Extending the Integration

### Adding New Charts

To add a new chart:

1. Create a new chart configuration in the `JSChartAdapter` module
2. Add a new chart type to the `send_chart_to_discord/3` function
3. Add the new chart to the `@chart_configs` list in the `ChartScheduler` module

### Customizing Chart Appearance

You can customize the appearance of the charts by modifying the chart configurations in the `JSChartAdapter` module. The following parameters can be adjusted:

- Chart dimensions (`@chart_width` and `@chart_height`)
- Background color (`@chart_background_color`)
- Text color (`@chart_text_color`)
- Chart options (titles, legends, scales, etc.)

## Troubleshooting

### Charts Not Appearing

If charts are not appearing in Discord:

1. Check that the EVE Corp Tools API is properly configured and accessible
2. Verify that the Discord notifier is working by sending a test message
3. Check the logs for any errors related to chart generation or sending
4. Use the TPS Data Inspector to verify that the TPS data is available and has the expected structure

### Invalid or Empty Charts

If charts appear but are invalid or empty:

1. Use the TPS Data Inspector to check the structure of the TPS data
2. Verify that the data extraction functions in the `JSChartAdapter` module are correctly mapping the TPS data
3. Check for any errors in the chart configuration

## Resources

- [EVE Corp Tools Service API Integration Guide](integration_api.md)
- [quickcharts.io Documentation](https://quickchart.io/documentation/)
- [Chart.js Documentation](https://www.chartjs.org/docs/latest/) 