# Logging Improvements Implementation Guide

This guide provides instructions for implementing the new structured logging approach throughout the codebase. The goal is to improve logging consistency, reduce noise, and make logs more useful for debugging and monitoring.

## Overview of Changes

We've created a new `WandererNotifier.Logger` module that provides:

1. Consistent category-based logging
2. Structured metadata support
3. Proper log level usage
4. Helper functions for common logging patterns

## Implementation Steps

### 1. Import the Logger Module

In each file you're updating, add:

```elixir
alias WandererNotifier.Logger, as: AppLogger
```

### 2. Replace Direct Logger Calls

Replace direct Elixir `Logger` calls with our category-specific helpers:

**Before:**

```elixir
Logger.info("Processing kill #{kill_id}")
```

**After:**

```elixir
AppLogger.kill_info("Processing killmail", kill_id: kill_id)
```

### 3. Move Implementation Details to Debug Level

Move detailed implementation logs to debug level:

**Before:**

```elixir
Logger.info("Found tracked character #{character_name} in killmail #{killmail_id}")
```

**After:**

```elixir
AppLogger.persistence_debug("Found tracked character",
  character_name: character_name,
  killmail_id: killmail_id
)
```

### 4. Use Structured Metadata Instead of String Interpolation

Replace string interpolation with structured metadata:

**Before:**

```elixir
Logger.error("Failed to process killmail #{killmail_id}: #{inspect(reason)}")
```

**After:**

```elixir
AppLogger.kill_error("Failed to process killmail",
  killmail_id: killmail_id,
  error: inspect(reason)
)
```

### 5. Consolidate Multiple Logs

Consolidate multiple related log messages into a single structured log:

**Before:**

```elixir
Logger.debug("Processing new kill #{kill_id}")
Logger.debug("Kill is in system #{system_name}")
Logger.info("Sending notification for kill #{kill_id}")
```

**After:**

```elixir
AppLogger.kill_info("Processing and sending notification",
  kill_id: kill_id,
  system_name: system_name,
  notification_sent: true
)
```

### 6. Use Lazy Evaluation for Expensive Logs

Use the `lazy_log` macro for logs that require expensive computations:

**Before:**

```elixir
Logger.debug("Complex data: #{inspect(large_data_structure)}")
```

**After:**

```elixir
AppLogger.lazy_log(:debug, "KILL", fn ->
  "Complex data: #{inspect(large_data_structure)}"
end)
```

### 7. Add Trace IDs for Related Operations

For multi-step operations, add trace IDs:

```elixir
def process_kill(kill_id) do
  trace_id = AppLogger.with_trace_id(operation: "process_kill")

  AppLogger.kill_info("Starting kill processing", kill_id: kill_id)

  # Processing steps...

  AppLogger.kill_info("Completed kill processing", kill_id: kill_id)
end
```

## Log Categories

Use the appropriate category for each type of log:

- `API` - For API interactions with external services
- `WEBSOCKET` - For WebSocket connections and messages
- `KILL` - For killmail processing
- `PERSISTENCE` - For database operations
- `PROCESSOR` - For message processing
- `CACHE` - For cache operations
- `STARTUP` - For application startup events
- `CONFIG` - For configuration loading
- `MAINTENANCE` - For maintenance tasks
- `SCHEDULER` - For scheduled operations

## Log Levels

Use the correct log level for each type of message:

- `debug` - Detailed troubleshooting information
- `info` - Normal operational events
- `warn` - Potential issues that aren't errors
- `error` - Errors that affect functionality

## Testing Your Changes

After updating logging in a module:

1. Run the application in development mode
2. Trigger the functionality you've updated
3. Verify that logs appear as expected with proper structure
4. Check that the log level is appropriate for each message

## Configuring Log Output

To use JSON formatting for logs, update your config:

```elixir
config :logger, :console,
  format: {WandererNotifier.Logger.JsonFormatter, :format},
  metadata: [:category, :trace_id, :module, :function]
```

## Next Steps

After implementing these logging improvements, we'll have:

1. Reduced log volume by moving implementation details to debug level
2. Improved log structure for better parsing and filtering
3. More consistent context in logs for better troubleshooting
4. Cleaner operational logs for monitoring system health
