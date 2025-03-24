# Logging Utilities

This document outlines the logging utilities and best practices in the WandererNotifier application.

## Overview

WandererNotifier uses a structured logging approach to provide comprehensive visibility into application behavior. The logging system is designed to facilitate troubleshooting, monitoring, and performance analysis across different components.

## Logging Architecture

The application uses Elixir's built-in Logger with custom formatters and backends to provide enhanced logging capabilities:

```elixir
config :logger,
  level: :info,
  backends: [:console, {LoggerFileBackend, :error_log}]

config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:module, :function, :trace_id, :category]
```

For structured logging in JSON format (recommended for production):

```elixir
config :logger, :console,
  format: {WandererNotifier.Logger.JsonFormatter, :format},
  metadata: [:module, :function, :trace_id, :category]
```

## Enhanced Logger Module

The application provides `WandererNotifier.Logger` to standardize logging across the codebase:

```elixir
alias WandererNotifier.Logger, as: AppLogger

# Category-specific logging with metadata
AppLogger.kill_info("Processing killmail",
  kill_id: "12345",
  system_name: "Jita"
)

# Exception logging with stack traces
AppLogger.exception(:error, "API", "Failed to fetch data", exception)

# Adding trace IDs for operation correlation
AppLogger.with_trace_id(operation: "process_killmail")
```

## Log Levels

The application uses the following log levels consistently:

| Level    | Purpose                              | Example Usage                             |
| -------- | ------------------------------------ | ----------------------------------------- |
| `:debug` | Detailed troubleshooting information | Cache hits/misses, WebSocket frames       |
| `:info`  | Normal operational events            | Service startup, scheduled task execution |
| `:warn`  | Potential issues that aren't errors  | Retrying API calls, fallback to defaults  |
| `:error` | Errors that affect functionality     | API failures, timeout errors, exceptions  |

## Log Categories

WandererNotifier uses standard categories in log messages for filtering and organization:

| Category      | Description                               |
| ------------- | ----------------------------------------- |
| `API`         | API interactions with external services   |
| `WEBSOCKET`   | WebSocket connection and message handling |
| `KILL`        | Killmail processing and notifications     |
| `PERSISTENCE` | Database operations and data storage      |
| `CACHE`       | Cache operations and performance          |
| `PROCESSOR`   | Message processing and transformation     |
| `STARTUP`     | Application startup events                |
| `CONFIG`      | Configuration loading and validation      |
| `MAINTENANCE` | Maintenance tasks and health checks       |
| `SCHEDULER`   | Scheduled task execution                  |

Examples:

```
[API] Fetching character data (character_id=12345, trace_id=abc123)
[KILL] Processing killmail (kill_id=67890, system_name="Jita")
```

## Structured Metadata

The logging system enriches log entries with contextual information as metadata:

```elixir
AppLogger.api_info("Fetching character data",
  character_id: character_id,
  method: "GET",
  endpoint: "/characters/#{character_id}/",
  cache_status: "miss"
)
```

This produces structured output that can be easily filtered and analyzed:

```json
{
  "timestamp": "2023-07-15T12:34:56.789Z",
  "level": "info",
  "message": "[API] Fetching character data",
  "category": "API",
  "character_id": 12345,
  "method": "GET",
  "endpoint": "/characters/12345/",
  "cache_status": "miss",
  "trace_id": "7a8b9c0d1e2f3g4h"
}
```

## Trace IDs

Trace IDs are used to correlate related log entries across different components:

```elixir
def process_message(message) do
  trace_id = AppLogger.with_trace_id(operation: "process_message")

  AppLogger.processor_info("Processing message")
  # Processing logic...
  AppLogger.processor_info("Message processing complete")
end
```

## Error Logging

Errors are logged with detailed information to facilitate troubleshooting:

```elixir
rescue
  error ->
    AppLogger.exception(:error, "API", "Failed to fetch data", error)
    {:error, :api_error}
end
```

## API Request/Response Logging

API interactions are logged with request and response details:

```elixir
def api_request(method, url, headers, body \\ nil) do
  sanitized_headers = sanitize_headers(headers)

  AppLogger.api_debug("Making API request",
    method: method,
    url: url,
    headers: sanitized_headers,
    body: body
  )

  # Make the request...

  AppLogger.api_debug("Received API response",
    status: status,
    headers: sanitized_headers,
    body: response_body
  )
end

defp sanitize_headers(headers) do
  Enum.map(headers, fn
    {key, _value} when key in ["Authorization", "authorization"] ->
      {key, "[REDACTED]"}
    header ->
      header
  end)
end
```

## Log File Management

The application configures log file rotation to prevent unbounded growth:

```elixir
config :logger, :error_log,
  path: "/var/log/wanderer_notifier/error.log",
  level: :error,
  format: {WandererNotifier.Logger.JsonFormatter, :format},
  metadata: [:module, :function, :trace_id, :category],
  rotate: %{max_bytes: 10_485_760, keep: 5}
```

## Startup Logging

The application logs comprehensive information at startup:

```elixir
AppLogger.startup_info("Starting application",
  version: Application.spec(:wanderer_notifier, :vsn),
  environment: Mix.env(),
  features_enabled: enabled_features()
)
```

## Runtime Logging Configuration

Log levels can be adjusted at runtime without restarting the application:

```elixir
# Increase verbosity for troubleshooting
Logger.configure(level: :debug)

# Reduce noise during normal operation
Logger.configure(level: :info)

# Adjust level for specific module
Logger.put_module_level(WandererNotifier.Api.Esi, :debug)
```

## Sensitive Data Handling

The application takes care to avoid logging sensitive information:

```elixir
def log_authentication(token) do
  # DON'T: Logger.info("Using token: #{token}")
  # DO:
  AppLogger.api_info("Authentication initiated", token: "[REDACTED]")
end
```

## Performance Considerations

The application implements performance-aware logging:

```elixir
# Lazy evaluation for expensive logs
AppLogger.lazy_log(:debug, "CACHE", fn ->
  "Cache stats: #{inspect(calculate_expensive_stats())}"
end)
```

## Best Practices

1. **Use Category Helpers** - Always use the appropriate category helper method
2. **Include Metadata** - Put context in metadata, not in message strings
3. **Proper Log Levels** - Use the right level for each type of information
4. **Consolidate Logs** - Group related information in a single log entry
5. **Add Trace IDs** - For multi-step operations to enable correlation
6. **Be Concise** - Keep messages clear and to the point
7. **Avoid String Interpolation** - Use structured metadata instead

## Environment Variables

Logging behavior can be configured via environment variables:

| Variable              | Description                         | Default |
| --------------------- | ----------------------------------- | ------- |
| `LOG_LEVEL`           | Main application log level          | `info`  |
| `LOG_API_LEVEL`       | API-specific log level              | `info`  |
| `LOG_WEBSOCKET_LEVEL` | WebSocket-specific log level        | `info`  |
| `ERROR_LOG_PATH`      | Path to error log file              | -       |
| `ENABLE_JSON_LOGGING` | Enable JSON-formatted logs          | `false` |
| `LOG_METADATA`        | Comma-separated metadata to include | -       |
