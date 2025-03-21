# Data Flow & Communication

This document details the data flow and communication patterns within the WandererNotifier application.

## Overview

WandererNotifier processes data from multiple external sources, transforms it into structured formats, and delivers notifications and visualizations based on this data. Understanding the data flow is crucial for maintaining and extending the application.

## Main Data Flow Paths

### 1. Data Acquisition

- **API clients** fetch data from external sources using dedicated modules:

  - Map API client retrieves systems and characters to track
  - ESI client fetches game data (characters, corporations, killmails)
  - zKillboard client provides real-time kill notifications via WebSocket
  - Corp Tools client retrieves TPS and other game metrics

- **URL builders** construct consistent API endpoints:

  - Each API has dedicated URL builder modules
  - Parameters are properly encoded and validated
  - URLs follow consistent patterns for each API

- **Response validators** ensure data integrity:
  - Validate response status codes
  - Check for expected data structure
  - Convert errors into standard result tuples (`{:error, reason}`)

### 2. Transformation & Structures

- **Raw API data** is converted to domain-specific structs:

  - `Character` - Character information with corporation and alliance details
  - `MapSystem` - Solar system data with tracking status
  - `Killmail` - Kill information with victim, attackers, and value
  - Other specialized structs for different data types

- **Validation** ensures data meets business requirements:

  - Required fields are present
  - Data types match expectations
  - Business rules are enforced (e.g., tracking limits)

- **Normalization** standardizes data formats:
  - Consistent field naming
  - Proper type conversion (strings to integers, ISO dates to DateTime)
  - Default values for missing fields

### 3. Processing & Caching

- **Validated data** is transformed for application use:

  - Additional fields calculated (e.g., system type from ID)
  - Data enriched from multiple sources
  - Complex business logic applied

- **Caching** with appropriate TTLs:

  - Time-sensitive data cached with short TTLs
  - Static reference data cached with longer TTLs
  - Cache repository provides consistent access patterns

- **Notification determination** logic decides when to notify:
  - Centralized determiner checks tracking status
  - Feature flags control notification types
  - Business rules determine notification criteria

### 4. Chart Generation

- **Chart configurations** are created with standardized `ChartConfig` structs:

  - Chart type, data points, labels, and options
  - Consistent format across different chart types
  - Theme settings optimized for Discord

- **Chart generation** processes the configurations:

  - Generator modules create chart data structures
  - External services render image representations
  - Images are optimized for Discord's dark theme

- **Fallback strategies** ensure resilience:
  - Alternative chart generation if primary method fails
  - Graceful degradation with text when images unavailable
  - Automatic retries with exponential backoff

### 5. Notification Delivery

- **Factory pattern** creates appropriate notifiers based on configuration:

  - Discord notifier for webhook delivery
  - Console notifier for development
  - Notifier behavior ensures consistent interface

- **Formatter** modules prepare data for each notification type:

  - Discord embeds with consistent styling
  - Color coding based on notification type
  - Links to relevant external resources

- **Delivery** mechanisms send the notification:
  - HTTP POST to Discord webhooks
  - Direct file attachments for charts
  - Fallback to text if rich formatting unavailable

## Component-Specific Data Flows

### WebSocket Data Flow

1. WebSocket connection established to zKillboard
2. Messages received in `handle_frame/2` function
3. JSON parsed and validated in `process_text_frame/2`
4. Valid kill messages passed to Kill Processor as `{:zkill_message, message}`
5. Killmail enriched with additional data from ESI API
6. Notification determination decides if notification needed
7. If needed, formatter creates Discord embed
8. Discord notifier sends embed to configured webhook

### Scheduler Data Flow

1. Scheduler started by Scheduler Supervisor
2. Based on configured timing (interval or specific time):
   - `IntervalScheduler` uses `Process.send_after/3` for periodic execution
   - `TimeScheduler` calculates next run time and schedules execution
3. When triggered, scheduler executes its configured task function
4. Task typically fetches data from an external API
5. Data processed and potentially triggers notifications
6. Results logged and scheduler schedules next execution
7. Registry keeps track of scheduler status and execution history

### Chart Generation Flow

1. Chart configuration created with data points and visualization options
2. Generator module transforms data into chart format
3. External service used to generate visual representation
4. Image data returned (as URL or base64)
5. Discord formatter incorporates chart into notification
6. Notification sent to configured Discord channel

### Character Tracking Flow

1. Map API queried for tracked characters
2. Response transformed to `Character` structs
3. New characters identified by comparing with cached data
4. Each new character evaluated for notification
5. If notification needed, character data enriched
6. Notification formatted with character portrait and details
7. Notification sent to Discord
8. Character data cached for future reference

### System Tracking Flow

1. Map API queried for tracked systems
2. Response transformed to `MapSystem` structs
3. Systems classified by ID pattern and API data
4. New systems identified by comparing with cached data
5. Each new system evaluated for notification
6. Static connections and recent kills fetched for context
7. Notification formatted with system details
8. Notification sent to Discord

## Sequence Diagrams

### Kill Notification Sequence

```
zKillboard WebSocket → WebSocket Handler → Kill Processor → ESI API
                                                           ↓
Discord Webhook ← Discord Notifier ← Formatter ← Notification Determiner
```

### Scheduled Chart Sequence

```
Scheduler Supervisor → Time Scheduler → Chart Task → Corp Tools API
                                                     ↓
Discord Webhook ← Discord Notifier ← Formatter ← Chart Generator
```

## Error Handling in Data Flow

- **Result tuples** consistently used throughout:

  - `{:ok, result}` for successful operations
  - `{:error, reason}` for failures

- **Error propagation** follows consistent patterns:

  - Early return from functions on error
  - `with` statements for multiple potential failure points
  - Error details preserved for debugging

- **Retry mechanisms** for transient failures:

  - Exponential backoff with jitter
  - Maximum retry attempts configurable
  - Different strategies based on error type

- **Circuit breakers** for external dependencies:
  - Prevent cascading failures
  - Automatic service health monitoring
  - Gradual recovery with half-open state

## Data Flow Optimization

- **Caching strategy** reduces API calls:

  - In-memory caching for frequent access
  - TTL-based expiration for freshness
  - Optimized key patterns for lookup efficiency

- **Batch processing** where possible:

  - Group API requests to reduce overhead
  - Process multiple items in single operation
  - Bulk inserts and updates

- **Lazy loading** for expensive operations:
  - Defer data enrichment until needed
  - Partial processing based on notification criteria
  - Progressive enhancement of notification data

## Data Flow Monitoring

- **Logging** at key points in the flow:

  - API requests and responses
  - Processing steps and transformations
  - Notification decisions and delivery

- **Telemetry** for performance metrics:

  - Processing time for each step
  - Cache hit/miss rates
  - API response times

- **Health checks** for external dependencies:
  - Periodic connectivity tests
  - Service availability monitoring
  - Automatic reporting of degraded services
