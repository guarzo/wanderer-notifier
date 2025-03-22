# Scheduler Validation Guide

## Overview

This document provides a comprehensive overview of all scheduled tasks in the WandererNotifier application, including what they do, when they run, and their implementation details. Use this guide to understand and validate the scheduled tasks in the system.

## Scheduler Architecture

The WandererNotifier application uses a well-structured scheduler system with the following components:

1. **Base Scheduler** (`BaseScheduler`): Provides common functionality for all schedulers
2. **Interval Scheduler** (`IntervalScheduler`): For tasks that run at regular intervals
3. **Time Scheduler** (`TimeScheduler`): For tasks that run at specific times of day
4. **Factory** (`Factory`): Creates the appropriate scheduler type based on configuration
5. **Registry** (`Registry`): Keeps track of all registered schedulers for management
6. **Supervisor** (`Supervisor`): Supervises all scheduler processes with a one_for_one strategy

All schedulers implement the `WandererNotifier.Schedulers.Behaviour`, ensuring consistent interface and functionality.

## Scheduled Tasks

### 1. TPS Chart Scheduler

**Module:** `WandererNotifier.Schedulers.TPSChartScheduler`

**What it does:**

- Retrieves TPS (Time, Pilots, Ships) data from Corp Tools API
- Generates charts using `TPSChartAdapter`
- Sends the charts to Discord

**When it runs:**

- Time-based scheduler, runs once a day at 12:00 UTC by default
- Hour is configurable via `WandererNotifier.Core.Config.Timings.tps_chart_hour()`
- Minute is configurable via `WandererNotifier.Core.Config.Timings.tps_chart_minute()`
- Can be overridden with environment variables `:tps_chart_schedule_hour` and `:tps_chart_schedule_minute`

**Enabled check:**

- Only runs if `WandererNotifier.Core.Config.corp_tools_enabled?()` returns true

**Implementation details:**

- Uses `CorpToolsClient.refresh_tps_data()` to get the latest data
- Waits 5 seconds after refreshing data to allow for processing
- Uses `TPSChartAdapter.send_all_charts_to_discord()` to generate and send charts
- Logs results for each chart type sent

### 2. Activity Chart Scheduler

**Module:** `WandererNotifier.Schedulers.ActivityChartScheduler`

**What it does:**

- Retrieves character activity data from Map API
- Generates character activity charts
- Sends charts to Discord through `ActivityChartAdapter`

**When it runs:**

- Interval-based scheduler, runs every 24 hours (24 _ 60 _ 60 \* 1000 milliseconds)
- Configured via `WandererNotifier.Core.Config.Timings.activity_chart_interval()`

**Enabled check:**

- Only runs if `WandererNotifier.Core.Config.map_charts_enabled?()` returns true

**Implementation details:**

- Uses `WandererNotifier.Api.Map.CharactersClient` to fetch activity data
- Generates charts for character activity showing connections, passages, and signatures
- Uses try/rescue blocks to handle chart generation failures
- Sends charts to Discord and logs success/failure for each chart type

### 3. Character Update Scheduler

**Module:** `WandererNotifier.Schedulers.CharacterUpdateScheduler`

**What it does:**

- Fetches character data from Map API
- Updates the list of tracked characters in cache
- Detects new characters for notifications

**When it runs:**

- Interval-based scheduler, runs every 30 minutes (30 _ 60 _ 1000 milliseconds)
- Configured via `WandererNotifier.Core.Config.Timings.character_update_scheduler_interval()`

**Enabled check:**

- Only runs if `WandererNotifier.Core.Config.map_charts_enabled?()` returns true

**Implementation details:**

- Retrieves existing cached characters for comparison
- Uses `WandererNotifier.Api.Map.CharactersClient.update_tracked_characters()` to update character data
- Stores results in cache with TTL of 24 hours
- Logs the number of characters updated or any errors encountered

### 4. System Update Scheduler

**Module:** `WandererNotifier.Schedulers.SystemUpdateScheduler`

**What it does:**

- Fetches solar system data from Map API
- Updates the list of tracked systems in cache
- Detects new systems for notifications

**When it runs:**

- Interval-based scheduler, runs every 60 minutes (60 _ 60 _ 1000 milliseconds)
- Configured via `WandererNotifier.Core.Config.Timings.system_update_scheduler_interval()`

**Enabled check:**

- Only runs if `WandererNotifier.Core.Config.map_charts_enabled?()` returns true

**Implementation details:**

- Uses `WandererNotifier.Api.Map.SystemsClient.update_systems()` to refresh system data
- Logs the number of systems updated
- Stores results in cache with appropriate TTL

### 5. Killmail Aggregation Scheduler

**Module:** `WandererNotifier.Schedulers.KillmailAggregationScheduler`

**What it does:**

- Aggregates killmail data into daily, weekly, and monthly statistics
- Generates statistics for tracked characters based on their killmails

**When it runs:**

- Time-based scheduler, runs once a day at 03:00 UTC
- Hour is configurable via environment variable `:killmail_aggregation_schedule_hour`
- Minute is configurable via environment variable `:killmail_aggregation_schedule_minute`

**Enabled check:**

- Only runs if `WandererNotifier.Core.Config.kill_charts_enabled?()` returns true

**Implementation details:**

- Uses `WandererNotifier.Resources.KillmailAggregation.aggregate_statistics/2` to generate statistics
- Special handling for weekly (Mondays) and monthly (1st of month) aggregation
- Logs results and any errors encountered during aggregation

### 6. Killmail Retention Scheduler

**Module:** `WandererNotifier.Schedulers.KillmailRetentionScheduler`

**What it does:**

- Cleans up old killmails based on retention policy
- Removes individual killmail records older than the retention period

**When it runs:**

- Time-based scheduler, runs once a day at 04:00 UTC
- Hour is configurable via environment variable `:killmail_retention_schedule_hour`
- Minute is configurable via environment variable `:killmail_retention_schedule_minute`

**Enabled check:**

- Only runs if `WandererNotifier.Core.Config.kill_charts_enabled?()` returns true

**Implementation details:**

- Uses `WandererNotifier.Resources.KillmailAggregation.cleanup_old_killmails/1` to remove old records
- Respects the retention period set in application configuration
- Logs the number of records cleaned up or any errors

### 7. Killmail Chart Scheduler

**Module:** `WandererNotifier.Schedulers.KillmailChartScheduler`

**What it does:**

- Generates weekly character kill charts
- Sends the charts to Discord for visibility

**When it runs:**

- Time-based scheduler, runs once a week on Sunday at 08:00 UTC
- Hour is configurable via environment variable `:killmail_chart_schedule_hour`
- Minute is configurable via environment variable `:killmail_chart_schedule_minute`

**Enabled check:**

- Only runs if `WandererNotifier.Core.Config.kill_charts_enabled?()` returns true

**Implementation details:**

- Only executes on Sundays (day 7 of the week)
- Generates a chart of the top 20 characters by kills in the past week
- Uses `WandererNotifier.ChartService.KillmailChartAdapter` to create the charts
- Sends charts to Discord via configured channel ID for kill charts
- Logs success or failure of chart generation and sending

## Scheduler Initialization and Management

Schedulers are initialized and managed through:

1. **Scheduler Supervisor** (`WandererNotifier.Schedulers.Supervisor`):

   - Started as part of the application supervision tree
   - Initializes the registry and all scheduler processes
   - Handles failures with a one_for_one strategy

2. **Scheduler Registry** (`WandererNotifier.Schedulers.Registry`):
   - Registers all scheduler modules
   - Provides functions to get information about all schedulers
   - Allows manual triggering of all registered schedulers

## Timing Configuration

All timing-related configurations are centralized in the `WandererNotifier.Core.Config.Timings` module, which provides:

- Cache TTLs
- Scheduler intervals
- Maintenance intervals
- Retry configurations
- WebSocket intervals

This centralization makes it easier to manage and adjust timing values without having to search through the codebase.

## Manual Scheduler Control

All schedulers can be manually triggered using their `execute_now/0` function, which is useful for testing and debugging.

Additionally, the Registry provides an `execute_all/0` function to trigger all registered schedulers simultaneously.

## Validating Schedulers

To validate that schedulers are working properly:

1. **Check Registry**: Verify that all schedulers are registered correctly:

   ```elixir
   WandererNotifier.Schedulers.Registry.list_registered()
   ```

2. **Manually Trigger**: Test a specific scheduler by manually triggering it:

   ```elixir
   WandererNotifier.Schedulers.TPSChartScheduler.execute_now()
   ```

3. **Check Logs**: Monitor logs for scheduler execution messages

   ```
   [info] TPS Chart Scheduler executing
   ```

4. **Verify Output**: Check Discord for the expected notifications or charts

## Best Practices

When working with schedulers:

1. Always use the centralized `Timings` module for configuration values
2. Implement proper error handling in scheduler execute functions
3. Include detailed logging for debugging purposes
4. Keep scheduler logic simple, delegating complex operations to service modules
5. Consider adding telemetry or metrics for monitoring scheduler health

## Recommendations for Improvement

If you're enhancing the scheduler system, consider:

1. Adding more comprehensive error handling for API failures
2. Implementing retry logic for transient errors in external API calls
3. Adding telemetry or metrics collection for scheduler execution
4. Implementing a web dashboard for scheduler status monitoring
