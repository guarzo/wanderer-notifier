# Logging Conventions

This document describes the logging conventions and best practices for the WandererNotifier application.

## Log Levels

- `AppLogger.debug/2` - Use for detailed developer information (only shown in dev mode)
- `AppLogger.info/2` - Use for normal operational messages
- `AppLogger.warn/2` - Use for concerning but non-critical issues
- `AppLogger.error/2` - Use for errors that impact functionality
- `AppLogger.critical/2` - Use for critical errors that require immediate attention

## Domain-Specific Loggers

- `AppLogger.api_debug/2` - For API call details
- `AppLogger.kill_info/2` - For killmail processing
- `AppLogger.kill_error/2` - For killmail processing errors
- `AppLogger.cache_debug/2` - For caching operations

## Metadata Guidelines

Always include relevant context with logs to make them searchable and useful:

### Required Metadata

- `module: __MODULE__` - Always include the module name
- `id: entity_id` - Include the primary entity ID (killmail ID, character ID, etc.)
- `error: inspect(reason)` - For error logs, always include the error details

### Additional Metadata

- `context_id: context.id` - Include request/operation context when available
- `source: "websocket"` - Identify the event source when important

## Examples

```elixir
# Good example with context
AppLogger.kill_info("Processing killmail", %{
  kill_id: km.killmail_id,
  module: __MODULE__,
  victim_id: km.victim_id
})

# Error logging with context
AppLogger.error("Failed to fetch data from ESI", %{
  module: __MODULE__,
  endpoint: "/endpoint",
  error: inspect(error),
  retry_count: retries
})
```

## Performance Considerations

- Avoid logging in tight loops unless needed
- Use `if Config.dev_mode?()` to guard verbose debug logs in production
- Do not log sensitive data (tokens, passwords, etc.)
