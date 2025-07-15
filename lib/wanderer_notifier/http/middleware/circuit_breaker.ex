defmodule WandererNotifier.Http.Middleware.CircuitBreaker do
  @moduledoc """
  HTTP middleware that implements circuit breaker pattern for HTTP requests.

  This middleware prevents cascading failures by monitoring request failures
  and temporarily blocking requests to failing services. It implements the
  classic circuit breaker pattern with three states: closed, open, and half-open.

  ## Features
  - Three-state circuit breaker (closed, open, half-open)
  - Configurable failure threshold and recovery timeout
  - Per-host circuit breaker isolation
  - Health check mechanism for recovery
  - Comprehensive logging of state transitions

  ## Circuit Breaker States
  - **Closed**: Normal operation, requests are allowed
  - **Open**: Circuit is open, requests are rejected immediately  
  - **Half-open**: Testing recovery, limited requests are allowed

  ## Usage

      # Simple circuit breaker with defaults
      Client.request(:get, "https://api.example.com/data", 
        middlewares: [CircuitBreaker])
      
      # Custom circuit breaker configuration
      Client.request(:get, "https://api.example.com/data", 
        middlewares: [CircuitBreaker],
        circuit_breaker_options: [
          failure_threshold: 10,
          recovery_timeout_ms: 30_000,
          error_status_codes: [500, 502, 503, 504]
        ])
  """

  @behaviour WandererNotifier.Http.Middleware.MiddlewareBehaviour

  alias WandererNotifier.Http.CircuitBreakerState
  alias WandererNotifier.Logger.Logger, as: AppLogger

  @type circuit_breaker_options :: [
          failure_threshold: pos_integer(),
          recovery_timeout_ms: pos_integer(),
          error_status_codes: [pos_integer()],
          enable_health_check: boolean(),
          context: String.t()
        ]

  @default_error_status_codes [500, 502, 503, 504, 408, 429]

  @doc """
  Executes the HTTP request with circuit breaker protection.

  The middleware will check the circuit breaker state before making requests
  and record successes/failures to manage state transitions. Circuit breaker
  behavior is configurable through the `:circuit_breaker_options` key.
  """
  @impl true
  def call(request, next) do
    options = get_circuit_breaker_options(request.opts)
    host = extract_host(request.url)

    # Check if request should be allowed
    case CircuitBreakerState.can_execute?(host) do
      true ->
        # Execute request and handle result
        execute_request(request, next, host, options)

      false ->
        # Circuit breaker is open - reject request
        log_circuit_breaker_rejection(host)
        {:error, {:circuit_breaker_open, "Circuit breaker is open for #{host}"}}
    end
  end

  # Private functions

  defp get_circuit_breaker_options(opts) do
    Keyword.get(opts, :circuit_breaker_options, [])
  end

  defp extract_host(url) do
    case URI.parse(url) do
      %URI{host: host} when is_binary(host) -> host
      _ -> "unknown"
    end
  end

  defp execute_request(request, next, host, options) do
    start_time = :erlang.system_time(:millisecond)

    try do
      result = next.(request)
      handle_response(result, host, options, start_time)
    rescue
      error ->
        # Exception occurred - record as failure
        duration_ms = :erlang.system_time(:millisecond) - start_time
        log_request_exception(host, error, duration_ms)
        CircuitBreakerState.record_failure(host)
        {:error, error}
    catch
      :exit, reason ->
        # Process exit - record as failure
        duration_ms = :erlang.system_time(:millisecond) - start_time
        log_request_exit(host, reason, duration_ms)
        CircuitBreakerState.record_failure(host)
        {:error, {:exit, reason}}
    end
  end

  defp handle_response({:ok, response} = result, host, options, start_time) do
    duration_ms = :erlang.system_time(:millisecond) - start_time
    error_status_codes = Keyword.get(options, :error_status_codes, @default_error_status_codes)

    if response.status_code in error_status_codes do
      # HTTP error status - record as failure
      log_request_failure(host, response.status_code, duration_ms)
      CircuitBreakerState.record_failure(host)
    else
      # Success - record it
      log_request_success(host, response.status_code, duration_ms)
      CircuitBreakerState.record_success(host)
    end

    result
  end

  defp handle_response({:error, reason} = result, host, _options, start_time) do
    duration_ms = :erlang.system_time(:millisecond) - start_time

    case reason do
      {:circuit_breaker_open, _message} ->
        # Don't record circuit breaker rejections as failures
        result

      _ ->
        # Network error or other failure - record it
        log_request_error(host, reason, duration_ms)
        CircuitBreakerState.record_failure(host)
        result
    end
  end

  # Logging functions

  defp log_circuit_breaker_rejection(host) do
    AppLogger.api_warn("Request rejected by circuit breaker", %{
      host: host,
      reason: "circuit_breaker_open",
      middleware: "CircuitBreaker"
    })
  end

  defp log_request_success(host, status_code, duration_ms) do
    AppLogger.api_debug("Circuit breaker: request succeeded", %{
      host: host,
      status_code: status_code,
      duration_ms: duration_ms,
      middleware: "CircuitBreaker"
    })
  end

  defp log_request_failure(host, status_code, duration_ms) do
    AppLogger.api_warn("Circuit breaker: request failed", %{
      host: host,
      status_code: status_code,
      duration_ms: duration_ms,
      reason: "http_error",
      middleware: "CircuitBreaker"
    })
  end

  defp log_request_error(host, reason, duration_ms) do
    AppLogger.api_warn("Circuit breaker: request error", %{
      host: host,
      error: inspect(reason),
      duration_ms: duration_ms,
      reason: "network_error",
      middleware: "CircuitBreaker"
    })
  end

  defp log_request_exception(host, error, duration_ms) do
    AppLogger.api_error("Circuit breaker: request exception", %{
      host: host,
      exception: inspect(error),
      duration_ms: duration_ms,
      reason: "exception",
      middleware: "CircuitBreaker"
    })
  end

  defp log_request_exit(host, reason, duration_ms) do
    AppLogger.api_error("Circuit breaker: request exit", %{
      host: host,
      exit_reason: inspect(reason),
      duration_ms: duration_ms,
      reason: "process_exit",
      middleware: "CircuitBreaker"
    })
  end
end
