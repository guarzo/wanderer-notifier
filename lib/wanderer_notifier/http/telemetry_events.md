# HTTP Telemetry Events Documentation

This document describes the telemetry events emitted by the HTTP middleware system for monitoring and observability.

## Event Overview

All HTTP telemetry events are emitted under the `[:wanderer_notifier, :http]` namespace and provide comprehensive instrumentation of HTTP request lifecycle, performance metrics, and error tracking.

## Events Reference

### Request Start: `[:wanderer_notifier, :http, :request_start]`

Emitted when an HTTP request is initiated.

**Measurements:**
- `timestamp` (integer) - System timestamp when the request started
- `request_size_bytes` (integer) - Total size of the HTTP request in bytes (includes method, URL, headers, and body)

**Metadata:**
- `method` (atom) - HTTP method (`:get`, `:post`, etc.)
- `host` (string) - Target host extracted from URL
- `service` (string) - Service name (configurable, defaults to host)
- `request_id` (string) - Unique identifier for the request
- `url` (string) - Request URL with sensitive query parameters masked
- Custom metadata as provided in telemetry options

### Request Finish: `[:wanderer_notifier, :http, :request_finish]`

Emitted when an HTTP request completes successfully.

**Measurements:**
- `timestamp` (integer) - System timestamp when the request finished
- `duration_ms` (integer) - Request duration in milliseconds
- `response_size_bytes` (integer) - Total size of the HTTP response in bytes (includes headers and body)

**Metadata:**
- `method` (atom) - HTTP method
- `host` (string) - Target host
- `service` (string) - Service name
- `request_id` (string) - Unique identifier for the request
- `status_code` (integer) - HTTP response status code
- `status_class` (string) - Status code class (`"2xx"`, `"3xx"`, `"4xx"`, `"5xx"`, `"unknown"`)
- `url` (string) - Request URL with sensitive query parameters masked
- Custom metadata as provided in telemetry options

### Request Error: `[:wanderer_notifier, :http, :request_error]`

Emitted when an HTTP request fails with an error.

**Measurements:**
- `timestamp` (integer) - System timestamp when the error occurred
- `duration_ms` (integer) - Request duration in milliseconds before failure

**Metadata:**
- `method` (atom) - HTTP method
- `host` (string) - Target host
- `service` (string) - Service name
- `request_id` (string) - Unique identifier for the request
- `error_type` (string) - Categorized error type (see Error Types below)
- `error` (string) - Human-readable error description
- `url` (string) - Request URL with sensitive query parameters masked
- Custom metadata as provided in telemetry options

### Request Exception: `[:wanderer_notifier, :http, :request_exception]`

Emitted when an HTTP request raises an exception or process exit.

**Measurements:**
- `timestamp` (integer) - System timestamp when the exception occurred
- `duration_ms` (integer) - Request duration in milliseconds before exception

**Metadata:**
- `method` (atom) - HTTP method
- `host` (string) - Target host
- `service` (string) - Service name
- `request_id` (string) - Unique identifier for the request
- `error_type` (string) - Always `"exception"`
- `exception` (string) - Exception details or exit reason
- `url` (string) - Request URL with sensitive query parameters masked
- Custom metadata as provided in telemetry options

## Error Types

The `error_type` field in error events categorizes failures for easier monitoring:

### Network Errors
- `"timeout"` - Request timeout
- `"connect_timeout"` - Connection timeout
- `"connection_refused"` - Connection refused (econnrefused)
- `"host_unreachable"` - Host unreachable (ehostunreach)
- `"network_unreachable"` - Network unreachable (enetunreach)
- `"connection_reset"` - Connection reset (econnreset)

### HTTP Errors
- `"http_2xx"` - HTTP 2xx status codes (if configured as errors)
- `"http_3xx"` - HTTP 3xx status codes (if configured as errors)
- `"http_4xx"` - HTTP 4xx status codes
- `"http_5xx"` - HTTP 5xx status codes

### Middleware Errors
- `"circuit_breaker_open"` - Request rejected by circuit breaker
- `"rate_limited"` - Request rejected by rate limiter

### Other
- `"unknown"` - Unrecognized error type
- `"exception"` - Exception or process exit

## Configuration

Telemetry behavior can be configured through the `:telemetry_options` key in request options:

```elixir
Client.request(:get, "https://api.example.com/data", 
  telemetry_options: [
    service_name: "external_api",           # Custom service name
    track_request_size: true,               # Include request size (default: true)
    track_response_size: true,              # Include response size (default: true)
    custom_metadata: %{team: "backend"},    # Additional metadata
    enable_detailed_logging: false         # Enable debug logging (default: false)
  ])
```

## Integration with Existing Telemetry

The HTTP telemetry middleware integrates with the existing `WandererNotifier.Telemetry` system:

- Calls `Telemetry.api_call/4` for each request to maintain compatibility
- Uses existing logging infrastructure for debug information
- Follows the same event naming convention as other telemetry events

## Example Usage

### Prometheus Metrics

```elixir
# In your telemetry supervisor
:telemetry.attach_many(
  "http-metrics",
  [
    [:wanderer_notifier, :http, :request_finish],
    [:wanderer_notifier, :http, :request_error],
    [:wanderer_notifier, :http, :request_exception]
  ],
  &HttpMetrics.handle_event/4,
  nil
)

defmodule HttpMetrics do
  def handle_event([:wanderer_notifier, :http, :request_finish], measurements, metadata, _config) do
    # Record success metrics
    :prometheus_counter.inc(:http_requests_total, [metadata.method, metadata.status_class, metadata.service])
    :prometheus_histogram.observe(:http_request_duration_seconds, [metadata.service], measurements.duration_ms / 1000)
    :prometheus_histogram.observe(:http_response_size_bytes, [metadata.service], measurements.response_size_bytes)
  end

  def handle_event([:wanderer_notifier, :http, :request_error], measurements, metadata, _config) do
    # Record error metrics
    :prometheus_counter.inc(:http_requests_total, [metadata.method, "error", metadata.service])
    :prometheus_counter.inc(:http_errors_total, [metadata.error_type, metadata.service])
  end

  # ... handle other events
end
```

### LiveDashboard Integration

The events are compatible with Phoenix LiveDashboard's telemetry charts:

```elixir
# In your router.ex
live_dashboard "/dashboard",
  metrics: [
    # Request rate
    Telemetry.Metrics.counter("wanderer_notifier.http.request_finish.count",
      tags: [:method, :status_class, :service]
    ),
    
    # Request duration
    Telemetry.Metrics.distribution("wanderer_notifier.http.request_finish.duration_ms",
      unit: {:millisecond, :duration},
      tags: [:service]
    ),
    
    # Error rate
    Telemetry.Metrics.counter("wanderer_notifier.http.request_error.count",
      tags: [:error_type, :service]
    )
  ]
```

## Security Considerations

- URLs are automatically masked to remove query parameters and fragments that may contain sensitive data
- Custom metadata should not include sensitive information
- Request/response bodies are never included in telemetry events
- Only headers' size is tracked, not their content