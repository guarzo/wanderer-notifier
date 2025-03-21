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
  metadata: [:module, :function, :trace_id]
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

WandererNotifier uses special tags in log messages to categorize and filter logs:

| Category Tag        | Description                                  |
| ------------------- | -------------------------------------------- |
| `[API TRACE]`       | API interactions with external services      |
| `[WEBSOCKET TRACE]` | WebSocket connection and message handling    |
| `[CACHE TRACE]`     | Cache operations and performance             |
| `[PROCESSOR TRACE]` | Message processing and transformation        |
| `[KILLMAIL TRACE]`  | Killmail-specific handling and notifications |
| `[FORMATTER TRACE]` | Discord message formatting and delivery      |
| `[SCHEDULER TRACE]` | Scheduled task execution                     |
| `[CONFIG TRACE]`    | Configuration loading and validation         |
| `[STARTUP TRACE]`   | Application startup events                   |

Example:

```
2023-06-01 12:34:56.789 [module=WebSocket][WEBSOCKET TRACE][info] Connected to zkillboard WebSocket
```

## Contextual Logging

The logging system enriches log entries with contextual information:

```elixir
Logger.metadata(
  module: __MODULE__,
  function: "#{function}/#{arity}",
  trace_id: trace_id
)

Logger.info("[API TRACE] Fetching character data for ID #{character_id}")
```

## Trace IDs

Trace IDs are used to correlate related log entries across different components:

```elixir
def process_message(message) do
  trace_id = generate_trace_id()
  Logger.metadata(trace_id: trace_id)

  Logger.info("[PROCESSOR TRACE] Processing message")
  # Processing logic...
  Logger.info("[PROCESSOR TRACE] Message processing complete")
end

defp generate_trace_id do
  Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)
end
```

## Structured Logging Helper

The `WandererNotifier.Logger` module provides helpers for consistent log formatting:

```elixir
defmodule WandererNotifier.Logger do
  require Logger

  def api_trace(message, metadata \\ []) do
    log(:info, "[API TRACE] #{message}", metadata)
  end

  def websocket_trace(message, metadata \\ []) do
    log(:info, "[WEBSOCKET TRACE] #{message}", metadata)
  end

  def cache_trace(message, metadata \\ []) do
    log(:debug, "[CACHE TRACE] #{message}", metadata)
  end

  # Additional helper methods for other trace types...

  defp log(level, message, metadata) do
    metadata = Keyword.merge(Logger.metadata(), metadata)
    Logger.log(level, message, metadata)
  end
end
```

## Error Logging

Errors are logged with detailed information to facilitate troubleshooting:

```elixir
rescue
  error ->
    stacktrace = Exception.format_stacktrace(__STACKTRACE__)
    Logger.error("[API TRACE] Failed to fetch data: #{inspect(error)}\n#{stacktrace}")
    {:error, :api_error}
end
```

## API Request/Response Logging

API interactions are logged with request and response details:

```elixir
def api_request_trace(method, url, headers, body \\ nil) do
  sanitized_headers = sanitize_headers(headers)
  Logger.debug(fn ->
    "[API TRACE] Request: #{method} #{url}\nHeaders: #{inspect(sanitized_headers)}\nBody: #{inspect(body)}"
  end)
end

def api_response_trace(status, headers, body) do
  sanitized_headers = sanitize_headers(headers)
  Logger.debug(fn ->
    "[API TRACE] Response: Status #{status}\nHeaders: #{inspect(sanitized_headers)}\nBody: #{inspect(body)}"
  end)
end

defp sanitize_headers(headers) do
  Enum.map(headers, fn
    {key, value} when key in ["Authorization", "authorization"] ->
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
  format: "$date $time $metadata[$level] $message\n",
  metadata: [:module, :function, :trace_id],
  rotate: %{max_bytes: 10_485_760, keep: 5}
```

## Startup Logging

The application logs comprehensive information at startup:

```elixir
Logger.info("[STARTUP TRACE] Starting WandererNotifier v#{Application.spec(:wanderer_notifier, :vsn)}")
Logger.info("[CONFIG TRACE] Environment: #{Mix.env()}")
Logger.info("[CONFIG TRACE] Features enabled: #{inspect(enabled_features())}")
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
  Logger.info("Authentication initiated with token: [REDACTED]")
end
```

## Log Analysis

Logs are designed to be easily parsed and analyzed using standard tools:

1. **Grep Patterns** - Logs use consistent patterns for easy filtering:

   ```bash
   grep "\[API TRACE\]" logs/application.log
   ```

2. **JSON Formatting** (optional) - Logs can be output in JSON format for advanced analysis:
   ```elixir
   config :logger, :console,
     format: {WandererNotifier.Logger.JsonFormatter, :format},
     metadata: [:module, :function, :trace_id, :category]
   ```

## Performance Considerations

The application implements performance-aware logging:

```elixir
# Avoid expensive operations when the level won't be logged
Logger.debug(fn -> "Computed value: #{expensive_computation()}" end)

# Rate-limited logging for frequent events
if should_log?(:websocket_message) do
  Logger.debug("[WEBSOCKET TRACE] Received message: #{inspect(message)}")
end

defp should_log?(event_type) do
  # Implement rate limiting based on event type
end
```

## Best Practices

1. **Use Appropriate Levels** - Select the correct log level based on message importance
2. **Include Context** - Always include relevant context (IDs, types, status)
3. **Use Categories** - Apply consistent category tags for filtering
4. **Be Concise** - Keep log messages clear and to the point
5. **Avoid Noise** - Don't log routine operations at info level during normal operation
6. **Correlate Events** - Use trace IDs to link related operations
7. **Sanitize Data** - Never log sensitive information like tokens or credentials
8. **Performance Aware** - Use lazy logging for expensive operations

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
