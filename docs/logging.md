# Logging Conventions

This document outlines the logging standards for the WandererNotifier application.

## Log Levels and Functions

The application uses the `AppLogger` module with the following severity functions:

| Function              | Use Case           | When to Use                                                |
| --------------------- | ------------------ | ---------------------------------------------------------- |
| `AppLogger.*_info/2`  | Normal operations  | Successfully processed operations, important state changes |
| `AppLogger.*_debug/2` | Detailed debugging | Development-only logs, fine-grained tracing                |
| `AppLogger.*_warn/2`  | Warning conditions | Potential issues that don't block operations               |
| `AppLogger.*_error/2` | Error conditions   | Failed operations, exceptions, unrecoverable states        |

## Context Categories

Each AppLogger function exists in several context-specific variants:

- `api_*` - External API calls (ESI, ZKill, etc.)
- `kill_*` - Killmail processing
- `processor_*` - Background processors
- `config_*` - Configuration-related operations
- `web_*` - Web/HTTP operations

Example: `AppLogger.api_error/2`, `AppLogger.kill_info/2`

## Required Metadata

All log calls MUST include identifying metadata as the second parameter:

```elixir
AppLogger.api_debug("Fetched killmail",
  kill_id: km.id,
  module: __MODULE__
)
```

### Required Keys

The following metadata keys are required for all log calls:

| Context         | Required Keys        |
| --------------- | -------------------- |
| All messages    | `module: __MODULE__` |
| API calls       | `endpoint`, `method` |
| Kill processing | `kill_id`            |
| Errors          | `error: reason`      |

### Common Optional Keys

Additional context-specific keys that should be included when available:

- `context_id` - ID of the processing context
- `system_id` - Solar system ID
- `character_id` - Character ID
- `duration_ms` - Operation duration in milliseconds

## Error Handling

When logging errors, always include the detailed error reason:

```elixir
# Good
AppLogger.api_error("ESI request failed",
  error: inspect(reason),
  endpoint: url
)

# Bad - missing error details
AppLogger.api_error("ESI request failed", endpoint: url)
```

### Error Formatting

- Use `inspect/1` for complex error terms
- Include both high-level error type and specific error details
- For exceptions, include exception type and message

## High-Volume Logs

For logs in tight loops or high-frequency operations:

1. Wrap in a conditional using `Config.dev_mode?/0` check
2. Use rate limiting (log once per minute/hour)
3. Use sampling (log only 1% of occurrences)

```elixir
if Config.dev_mode?() do
  AppLogger.processor_debug("Processing item", item_id: id)
end
```

## Correlation

To correlate related log entries across a processing flow:

1. Generate a unique ID at the entry point
2. Pass this ID through the entire processing chain
3. Include it in all log messages as `correlation_id`

## Testing

Avoid excessive logging in tests. In test environment:

1. Set higher log levels to reduce noise
2. Add custom log assertions only for critical paths
3. Use tagged logs to easily identify test-related entries
