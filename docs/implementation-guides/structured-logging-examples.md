# Structured Logging Examples

This guide provides examples of how to convert traditional string-interpolated logs to structured metadata format.

## Key Principles

1. Move variable data from message strings to metadata
2. Keep message text clear and consistent
3. Use category-specific helper functions
4. Apply appropriate log levels

## Example Transformations

### Basic Log Conversion

**Before:**

```elixir
Logger.info("Processing character #{character_id} with name #{character_name}")
```

**After:**

```elixir
AppLogger.persistence_info("Processing character",
  character_id: character_id,
  character_name: character_name
)
```

### Error Logging Conversion

**Before:**

```elixir
Logger.error("Failed to retrieve character #{character_id} from API: #{inspect(error)}")
```

**After:**

```elixir
AppLogger.api_error("Failed to retrieve character",
  character_id: character_id,
  error: inspect(error)
)
```

### Conditional Debug Logging

**Before:**

```elixir
if verbose_mode? do
  Logger.debug("Cache hit for key #{key}, value: #{inspect(value)}")
end
```

**After:**

```elixir
if verbose_mode? do
  AppLogger.cache_debug("Cache hit",
    key: key,
    value: inspect(value)
  )
end
```

### Error With Stacktrace

**Before:**

```elixir
rescue
  e ->
    stacktrace = Exception.format_stacktrace(__STACKTRACE__)
    Logger.error("Exception during processing: #{Exception.message(e)}\n#{stacktrace}")
    {:error, :internal_error}
end
```

**After:**

```elixir
rescue
  e ->
    AppLogger.cache_error("Exception during processing",
      error: Exception.message(e),
      stacktrace: Exception.format_stacktrace(__STACKTRACE__)
    )
    {:error, :internal_error}
end
```

### Lazy Logging for Expensive Operations

**Before:**

```elixir
Logger.debug(fn -> "Complex data structure: #{inspect(large_data, limit: 10000)}" end)
```

**After:**

```elixir
AppLogger.lazy_log(:debug, "PROCESSOR", fn ->
  data_str = inspect(large_data, limit: 10000)
  "Complex data inspection complete"
end, data_size: byte_size(inspect(large_data)))
```

### Trace IDs for Request Correlation

**Before:**

```elixir
def process_request(request) do
  request_id = generate_id()
  Logger.metadata(request_id: request_id)
  Logger.info("Processing request #{request_id}")
  # ... processing logic
  Logger.info("Request #{request_id} complete")
end
```

**After:**

```elixir
def process_request(request) do
  trace_id = AppLogger.with_trace_id(operation: "process_request")

  AppLogger.api_info("Processing request", request_id: extract_id(request))
  # ... processing logic
  AppLogger.api_info("Request complete")
end
```

## Category Cheat Sheet

| Module Type             | Category      | Example                                                               |
| ----------------------- | ------------- | --------------------------------------------------------------------- |
| API/HTTP/External       | `api`         | `AppLogger.api_info("API request sent", url: url)`                    |
| WebSocket               | `websocket`   | `AppLogger.websocket_debug("Message received", size: byte_size(msg))` |
| Database/Persistence    | `persistence` | `AppLogger.persistence_info("Record created", id: record.id)`         |
| Cache                   | `cache`       | `AppLogger.cache_debug("Cache hit", key: cache_key)`                  |
| Schedulers/Jobs         | `scheduler`   | `AppLogger.scheduler_info("Job started", job_id: job.id)`             |
| Service Initialization  | `startup`     | `AppLogger.startup_info("Service started", port: port)`               |
| Configuration           | `config`      | `AppLogger.config_info("Config loaded", environment: env)`            |
| Message/Kill Processing | `processor`   | `AppLogger.processor_info("Message processed", msg_id: id)`           |
| Maintenance Tasks       | `maintenance` | `AppLogger.maintenance_info("Maintenance complete")`                  |

## Common Pitfalls

1. **Don't** use string interpolation in the message - move variable data to metadata
2. **Don't** include module name prefixes in messages - that's handled by the category
3. **Don't** log sensitive data - always redact credentials, tokens, etc.
4. **Don't** overuse `info` level - use `debug` for most implementation details

## Recommended Structure

Follow this general structure for most log calls:

```elixir
AppLogger.{category}_{level}("{clear action or status message}",
  # Add relevant metadata for filtering and context
  id: id,
  status: status,
  count: items_processed
)
```
