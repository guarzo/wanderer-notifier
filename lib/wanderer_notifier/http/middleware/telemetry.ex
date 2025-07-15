defmodule WandererNotifier.Http.Middleware.Telemetry do
  @moduledoc """
  HTTP middleware that provides comprehensive telemetry and metrics collection.

  This middleware instruments HTTP requests with telemetry events and metrics,
  tracking request lifecycle, performance metrics, error rates, and request/response
  sizes. It integrates with the existing WandererNotifier.Telemetry system.

  ## Metrics Collected
  - Request duration (milliseconds)
  - HTTP status codes and error rates
  - Request and response body sizes
  - Host-specific metrics
  - Error categorization (network, HTTP, timeouts)

  ## Telemetry Events
  All events are emitted under the `[:wanderer_notifier, :http]` namespace:
  - `[:wanderer_notifier, :http, :request_start]` - Request initiated
  - `[:wanderer_notifier, :http, :request_finish]` - Request completed successfully
  - `[:wanderer_notifier, :http, :request_error]` - Request failed with error
  - `[:wanderer_notifier, :http, :request_exception]` - Request raised an exception

  ## Usage

      # Simple telemetry with defaults
      Client.request(:get, "https://api.example.com/data", 
        middlewares: [Telemetry])
      
      # Custom telemetry configuration
      Client.request(:get, "https://api.example.com/data", 
        middlewares: [Telemetry],
        telemetry_options: [
          service_name: "external_api",
          track_request_size: true,
          track_response_size: true,
          custom_metadata: %{team: "backend"}
        ])
  """

  @behaviour WandererNotifier.Http.Middleware.MiddlewareBehaviour

  alias WandererNotifier.Telemetry
  alias WandererNotifier.Logger.Logger, as: AppLogger

  @type telemetry_options :: [
          service_name: String.t(),
          track_request_size: boolean(),
          track_response_size: boolean(),
          custom_metadata: map(),
          enable_detailed_logging: boolean()
        ]

  @doc """
  Executes the HTTP request with comprehensive telemetry instrumentation.

  Collects metrics for request duration, status codes, error rates, and sizes.
  Emits telemetry events throughout the request lifecycle for monitoring and
  observability. Configuration is available through `:telemetry_options`.
  """
  @impl true
  def call(request, next) do
    options = get_telemetry_options(request.opts)
    context = build_telemetry_context(request, options)

    start_time = :erlang.system_time(:millisecond)
    monotonic_start = :erlang.monotonic_time(:millisecond)

    # Emit request start event
    emit_request_start(context, request)

    try do
      result = next.(request)
      handle_result(result, context, start_time, monotonic_start, options)
    rescue
      error ->
        # Handle exceptions during request
        handle_exception(error, context, start_time, monotonic_start)
        reraise error, __STACKTRACE__
    catch
      :exit, reason ->
        # Handle process exits
        handle_exit(reason, context, start_time, monotonic_start)
        exit(reason)
    end
  end

  # Private functions

  defp get_telemetry_options(opts) do
    Keyword.get(opts, :telemetry_options, [])
  end

  defp build_telemetry_context(request, options) do
    host = extract_host(request.url)
    service_name = Keyword.get(options, :service_name, host)

    %{
      method: request.method,
      url: request.url,
      host: host,
      service_name: service_name,
      request_id: generate_request_id(),
      custom_metadata: Keyword.get(options, :custom_metadata, %{})
    }
  end

  defp extract_host(url) do
    case URI.parse(url) do
      %URI{host: host} when is_binary(host) -> host
      _ -> "unknown"
    end
  end

  defp generate_request_id do
    :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
  end

  defp emit_request_start(context, request) do
    request_size = calculate_request_size(request)

    measurements = %{
      timestamp: :erlang.system_time(:millisecond),
      request_size_bytes: request_size
    }

    metadata =
      %{
        method: context.method,
        host: context.host,
        service: context.service_name,
        request_id: context.request_id,
        url: mask_sensitive_url(context.url)
      }
      |> Map.merge(context.custom_metadata)

    :telemetry.execute([:wanderer_notifier, :http, :request_start], measurements, metadata)

    log_request_start(context, request_size)
  end

  defp handle_result({:ok, response} = result, context, start_time, monotonic_start, options) do
    duration_ms = :erlang.system_time(:millisecond) - start_time
    monotonic_duration = :erlang.monotonic_time(:millisecond) - monotonic_start

    response_size =
      if Keyword.get(options, :track_response_size, true) do
        calculate_response_size(response)
      else
        0
      end

    # Emit telemetry for successful request
    emit_request_finish(context, response, monotonic_duration, response_size)

    # Record API call telemetry using existing system
    Telemetry.api_call(context.service_name, context.url, duration_ms, true)

    log_request_success(context, response, duration_ms, response_size)

    result
  end

  defp handle_result({:error, reason} = result, context, start_time, monotonic_start, _options) do
    duration_ms = :erlang.system_time(:millisecond) - start_time
    monotonic_duration = :erlang.monotonic_time(:millisecond) - monotonic_start

    # Emit telemetry for failed request
    emit_request_error(context, reason, monotonic_duration)

    # Record API call telemetry using existing system
    Telemetry.api_call(context.service_name, context.url, duration_ms, false)

    log_request_error(context, reason, duration_ms)

    result
  end

  defp handle_exception(error, context, start_time, monotonic_start) do
    duration_ms = :erlang.system_time(:millisecond) - start_time
    monotonic_duration = :erlang.monotonic_time(:millisecond) - monotonic_start

    # Emit telemetry for exception
    emit_request_exception(context, error, monotonic_duration)

    # Record API call telemetry using existing system
    Telemetry.api_call(context.service_name, context.url, duration_ms, false)

    log_request_exception(context, error, duration_ms)
  end

  defp handle_exit(reason, context, start_time, monotonic_start) do
    duration_ms = :erlang.system_time(:millisecond) - start_time
    monotonic_duration = :erlang.monotonic_time(:millisecond) - monotonic_start

    # Emit telemetry for process exit
    emit_request_exception(context, {:exit, reason}, monotonic_duration)

    # Record API call telemetry using existing system
    Telemetry.api_call(context.service_name, context.url, duration_ms, false)

    log_request_exit(context, reason, duration_ms)
  end

  defp emit_request_finish(context, response, duration_ms, response_size) do
    measurements = %{
      timestamp: :erlang.system_time(:millisecond),
      duration_ms: duration_ms,
      response_size_bytes: response_size
    }

    metadata =
      %{
        method: context.method,
        host: context.host,
        service: context.service_name,
        request_id: context.request_id,
        status_code: response.status_code,
        status_class: status_class(response.status_code),
        url: mask_sensitive_url(context.url)
      }
      |> Map.merge(context.custom_metadata)

    :telemetry.execute([:wanderer_notifier, :http, :request_finish], measurements, metadata)
  end

  defp emit_request_error(context, reason, duration_ms) do
    measurements = %{
      timestamp: :erlang.system_time(:millisecond),
      duration_ms: duration_ms
    }

    metadata =
      %{
        method: context.method,
        host: context.host,
        service: context.service_name,
        request_id: context.request_id,
        error_type: categorize_error(reason),
        error: format_error_for_telemetry(reason),
        url: mask_sensitive_url(context.url)
      }
      |> Map.merge(context.custom_metadata)

    :telemetry.execute([:wanderer_notifier, :http, :request_error], measurements, metadata)
  end

  defp emit_request_exception(context, error, duration_ms) do
    measurements = %{
      timestamp: :erlang.system_time(:millisecond),
      duration_ms: duration_ms
    }

    metadata =
      %{
        method: context.method,
        host: context.host,
        service: context.service_name,
        request_id: context.request_id,
        error_type: "exception",
        exception: format_exception_for_telemetry(error),
        url: mask_sensitive_url(context.url)
      }
      |> Map.merge(context.custom_metadata)

    :telemetry.execute([:wanderer_notifier, :http, :request_exception], measurements, metadata)
  end

  defp calculate_request_size(request) do
    body_size = calculate_body_size(request.body)
    headers_size = calculate_headers_size(request.headers)
    url_size = byte_size(request.url)
    method_size = request.method |> to_string() |> byte_size()

    body_size + headers_size + url_size + method_size
  end

  defp calculate_body_size(nil), do: 0
  defp calculate_body_size(body) when is_binary(body), do: byte_size(body)
  defp calculate_body_size(body) when is_map(body), do: body |> Jason.encode!() |> byte_size()
  defp calculate_body_size(_), do: 0

  defp calculate_headers_size(headers) do
    headers
    |> Enum.reduce(0, fn {key, value}, acc ->
      # +4 for ": " and "\r\n"
      acc + byte_size(key) + byte_size(value) + 4
    end)
  end

  defp calculate_response_size(response) do
    body_size =
      case response.body do
        body when is_binary(body) -> byte_size(body)
        body when is_map(body) -> body |> Jason.encode!() |> byte_size()
        _ -> 0
      end

    headers_size =
      Map.get(response, :headers, [])
      |> Enum.reduce(0, fn {key, value}, acc ->
        # +4 for ": " and "\r\n"
        acc + byte_size(key) + byte_size(value) + 4
      end)

    body_size + headers_size
  end

  defp status_class(status_code) when status_code >= 200 and status_code < 300, do: "2xx"
  defp status_class(status_code) when status_code >= 300 and status_code < 400, do: "3xx"
  defp status_class(status_code) when status_code >= 400 and status_code < 500, do: "4xx"
  defp status_class(status_code) when status_code >= 500 and status_code < 600, do: "5xx"
  defp status_class(_), do: "unknown"

  defp categorize_error({:http_error, status_code, _body}),
    do: "http_#{status_class(status_code)}"

  defp categorize_error(:timeout), do: "timeout"
  defp categorize_error(:connect_timeout), do: "connect_timeout"
  defp categorize_error(:econnrefused), do: "connection_refused"
  defp categorize_error(:ehostunreach), do: "host_unreachable"
  defp categorize_error(:enetunreach), do: "network_unreachable"
  defp categorize_error(:econnreset), do: "connection_reset"
  defp categorize_error({:circuit_breaker_open, _}), do: "circuit_breaker_open"
  defp categorize_error({:rate_limited, _}), do: "rate_limited"
  defp categorize_error(_), do: "unknown"

  defp format_error_for_telemetry({:http_error, status_code, _body}), do: "HTTP #{status_code}"

  defp format_error_for_telemetry({:circuit_breaker_open, message}),
    do: "Circuit breaker: #{message}"

  defp format_error_for_telemetry({:rate_limited, message}), do: "Rate limited: #{message}"
  defp format_error_for_telemetry(error) when is_atom(error), do: to_string(error)
  defp format_error_for_telemetry({error, _details}) when is_atom(error), do: to_string(error)
  defp format_error_for_telemetry(error), do: inspect(error)

  defp format_exception_for_telemetry({:exit, reason}), do: "Exit: #{inspect(reason)}"
  defp format_exception_for_telemetry(error), do: inspect(error)

  defp mask_sensitive_url(url) do
    # Remove query parameters and fragments that might contain sensitive data
    try do
      uri = URI.parse(url)

      %{uri | query: nil, fragment: nil}
      |> URI.to_string()
    rescue
      _ ->
        # If URI parsing fails, return original URL
        url
    end
  end

  # Logging functions

  defp log_request_start(context, request_size) do
    AppLogger.api_debug("HTTP request telemetry started", %{
      method: context.method,
      host: context.host,
      service: context.service_name,
      request_id: context.request_id,
      request_size_bytes: request_size,
      middleware: "Telemetry"
    })
  end

  defp log_request_success(context, response, duration_ms, response_size) do
    AppLogger.api_debug("HTTP request telemetry completed", %{
      method: context.method,
      host: context.host,
      service: context.service_name,
      request_id: context.request_id,
      status_code: response.status_code,
      duration_ms: duration_ms,
      response_size_bytes: response_size,
      middleware: "Telemetry"
    })
  end

  defp log_request_error(context, reason, duration_ms) do
    AppLogger.api_warn("HTTP request telemetry error", %{
      method: context.method,
      host: context.host,
      service: context.service_name,
      request_id: context.request_id,
      error_type: categorize_error(reason),
      error: format_error_for_telemetry(reason),
      duration_ms: duration_ms,
      middleware: "Telemetry"
    })
  end

  defp log_request_exception(context, error, duration_ms) do
    AppLogger.api_error("HTTP request telemetry exception", %{
      method: context.method,
      host: context.host,
      service: context.service_name,
      request_id: context.request_id,
      exception: format_exception_for_telemetry(error),
      duration_ms: duration_ms,
      middleware: "Telemetry"
    })
  end

  defp log_request_exit(context, reason, duration_ms) do
    AppLogger.api_error("HTTP request telemetry process exit", %{
      method: context.method,
      host: context.host,
      service: context.service_name,
      request_id: context.request_id,
      exit_reason: inspect(reason),
      duration_ms: duration_ms,
      middleware: "Telemetry"
    })
  end
end
