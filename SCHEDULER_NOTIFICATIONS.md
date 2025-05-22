# Scheduler and Notification System Documentation

## Overview

The system consists of two main components:

1. Schedulers for periodic updates of character and system data
2. Notification system for sending updates to configured channels

## Scheduler System

### Base Scheduler Implementation

The `BaseMapScheduler` module provides common functionality for map-related schedulers:

- Initializes with configurable update interval
- Manages cached data in Cachex
- Handles periodic updates and error recovery
- Provides logging and monitoring capabilities

#### Key Features

- **Configurable Intervals**: Each scheduler can have its own update interval
- **Caching**: Uses Cachex for data persistence between updates
- **Error Handling**: Implements retry logic with exponential backoff
- **Logging**: Comprehensive logging of scheduler operations

#### Scheduler Lifecycle

1. **Initialization**:

   - Loads cached data if available
   - Sets up initial state with interval and timer
   - Checks feature flag status

2. **Update Cycle**:

   - Fetches new data from API
   - Compares with cached data
   - Updates cache with new data
   - Schedules next update

3. **Error Recovery**:
   - Implements retry logic for failed updates
   - Uses shorter intervals for retry attempts
   - Logs error details for debugging

## Notification System

### Notification Dispatcher

The `WandererNotifier.Notifications.Dispatcher` module handles all notification routing:

- Supports multiple notification types
- Configurable notification channels
- First-run notification handling
- Discord integration

#### Notification Types

1. **System Notifications**:

   - System status updates
   - System kill notifications
   - Configurable channel routing

2. **Character Notifications**:

   - Character activity updates
   - Character kill notifications
   - Separate channel support

3. **Status Notifications**:
   - Application status updates
   - Periodic health checks
   - System-wide announcements

#### First Run Handling

- Tracks first notification per type
- Skips notifications on first run
- Maintains state in Stats module
- Prevents duplicate notifications

### Killmail Enrichment

The `WandererNotifier.Killmail.Enrichment` module enhances killmail data:

- ESI data enrichment
- Victim information lookup
- Attacker details enrichment
- System information addition

#### Enrichment Features

1. **Victim Information**:

   - Character name
   - Corporation details
   - Alliance information
   - Ship type and name

2. **Attacker Information**:

   - Character names
   - Corporation details
   - Alliance information
   - Ship types

3. **System Information**:
   - System name
   - System ID
   - Recent kill history

## Configuration

### Scheduler Configuration

```elixir
config :wanderer_notifier,
  scheduler_interval: 60_000,  # 1 minute
  cache_name: :wanderer_cache
```

### Notification Configuration

```elixir
config :wanderer_notifier,
  notifications_enabled: true,
  discord_channel_id: "channel_id",
  discord_system_kill_channel_id: "system_channel_id",
  discord_character_kill_channel_id: "character_channel_id"
```

## Best Practices

1. **Scheduler Management**:

   - Monitor scheduler health
   - Review logs for errors
   - Adjust intervals based on load
   - Implement proper error handling

2. **Notification Handling**:

   - Verify channel configurations
   - Monitor notification delivery
   - Review first-run behavior
   - Check enrichment quality

3. **Data Management**:
   - Regular cache cleanup
   - Monitor data freshness
   - Validate enriched data
   - Handle API rate limits

## Troubleshooting

### Common Issues

1. **Scheduler Stops**:

   - Check feature flags
   - Review error logs
   - Verify API connectivity
   - Check cache status

2. **Missing Notifications**:

   - Verify notification settings
   - Check channel configurations
   - Review first-run status
   - Validate data enrichment

3. **Enrichment Issues**:
   - Check ESI service status
   - Verify API credentials
   - Review rate limits
   - Check data format

### Debugging Steps

1. Enable debug logging
2. Check scheduler state
3. Verify notification settings
4. Review enrichment process
5. Monitor API responses

## Future Improvements

1. **Scheduler Enhancements**:

   - Dynamic interval adjustment
   - Better error recovery
   - Enhanced monitoring
   - Performance optimization

2. **Notification Improvements**:

   - Additional notification types
   - Enhanced formatting
   - Better channel management
   - Rate limiting

3. **Enrichment Improvements**:
   - Caching improvements
   - Better error handling
   - Additional data sources
   - Performance optimization
