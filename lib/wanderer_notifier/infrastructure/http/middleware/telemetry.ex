defmodule WandererNotifier.Infrastructure.Http.Middleware.Telemetry do
  @moduledoc """
  Simplified HTTP telemetry middleware for essential metrics only.

  This lightweight version focuses on the most important metrics:
  - Request duration
  - HTTP status codes  
  - Service identification
  - Basic error tracking

  Removed complex features:
  - Request/response size calculation
  - Detailed error categorization
  - Complex logging redundant with other systems
  - Unique request ID generation
  """

  @behaviour WandererNotifier.Infrastructure.Http.Middleware.MiddlewareBehaviour

  # HTTPoison is used in pattern matching for error classification
  alias HTTPoison.Error, as: HTTPoisonError

  @doc """
  Executes telemetry middleware to track HTTP request metrics.
  """
  def call(request, next) do
    start_time = System.monotonic_time(:millisecond)
    service = extract_service(request)
    host = extract_host(request.url)

    try do
      result = next.(request)
      duration = System.monotonic_time(:millisecond) - start_time
      status = extract_status(result)

      # Emit success telemetry
      :telemetry.execute(
        [:wanderer_notifier, :http, :request],
        %{duration: duration},
        %{
          method: request.method,
          service: service,
          host: host,
          status: status
        }
      )

      result
    rescue
      error ->
        duration = System.monotonic_time(:millisecond) - start_time

        # Emit error telemetry
        :telemetry.execute(
          [:wanderer_notifier, :http, :request],
          %{duration: duration},
          %{
            method: request.method,
            service: service,
            host: host,
            status: :error,
            error_type: classify_error(error)
          }
        )

        reraise error, __STACKTRACE__
    end
  end

  # Extract service name from request options
  defp extract_service(request) do
    request.opts
    |> Keyword.get(:service, :unknown)
    |> to_string()
  end

  # Extract host from URL
  defp extract_host(url) when is_binary(url) do
    case URI.parse(url) do
      %URI{host: host} when is_binary(host) -> host
      _ -> "unknown"
    end
  end

  # Extract status from response
  defp extract_status({:ok, %{status_code: status_code}}) when is_integer(status_code) do
    status_code
  end

  defp extract_status({:error, _reason}) do
    :error
  end

  defp extract_status(_) do
    :unknown
  end

  # Simple error classification
  defp classify_error(%HTTPoisonError{reason: reason}) do
    case reason do
      :timeout -> :timeout
      :nxdomain -> :dns
      :econnrefused -> :connection
      _ -> :http_error
    end
  end

  defp classify_error(_error) do
    :unknown_error
  end
end
