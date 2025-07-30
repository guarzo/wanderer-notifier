defmodule WandererNotifier.Infrastructure.Http.Middleware.Retry do
  require Logger

  @moduledoc """
  HTTP middleware that implements retry logic with exponential backoff and jitter.

  This middleware wraps HTTP requests with configurable retry logic, handling
  transient failures gracefully. It uses the shared WandererNotifier.Shared.Utils.Retry
  utility for consistent retry behavior across the application.

  ## Features
  - Exponential backoff with optional jitter
  - Configurable retry attempts and timeouts
  - Selective retry based on error types and HTTP status codes
  - Comprehensive logging of retry attempts

  ## Usage

      # Simple retry with defaults
      Client.request(:get, "https://api.example.com/data",
        middlewares: [Retry])

      # Custom retry configuration
      Client.request(:get, "https://api.example.com/data",
        middlewares: [Retry],
        retry_options: [
          max_attempts: 5,
          base_backoff: 1000,
          retryable_errors: [:timeout, :econnrefused]
        ])
  """

  @behaviour WandererNotifier.Infrastructure.Http.Middleware.MiddlewareBehaviour

  alias WandererNotifier.Shared.Utils.Retry, as: RetryUtils

  @type retry_options :: [
          max_attempts: pos_integer(),
          base_backoff: pos_integer(),
          max_backoff: pos_integer(),
          jitter: boolean(),
          retryable_errors: [atom()],
          retryable_status_codes: [pos_integer()],
          context: String.t()
        ]

  @default_retryable_status_codes [408, 429, 500, 502, 503, 504]
  @default_retryable_errors [
    :timeout,
    :connect_timeout,
    :econnrefused,
    :ehostunreach,
    :enetunreach,
    :econnreset
  ]

  @doc """
  Executes the HTTP request with retry logic applied.

  The middleware will retry requests that fail with retryable errors or
  return retryable HTTP status codes. Retry behavior is configurable
  through the `:retry_options` key in the request options.
  """
  @impl true
  def call(request, next) do
    retry_options = get_retry_options(request.opts)
    context = build_context(request)
    retry_fun = build_retry_function(request, next, retry_options)

    execute_with_retry(retry_fun, retry_options, context)
  end

  # Private functions

  defp build_retry_function(request, next, retry_options) do
    fn ->
      result = next.(request)
      handle_result(result, retry_options)
    end
  end

  defp handle_result({:ok, response}, retry_options) do
    if retryable_status_code?(response.status_code, retry_options) do
      # Convert to error for retry logic, but preserve original response
      {:error, {:retryable_http_status, response}}
    else
      # Success - no retry needed
      {:ok, response}
    end
  end

  defp handle_result({:error, reason} = result, retry_options) do
    if retryable_error?(reason, retry_options) do
      # For HTTP error tuples, convert to a format the retry utility understands
      case reason do
        {:http_error, status_code, _body} when status_code in [408, 429, 500, 502, 503, 504] ->
          {:error, :http_error}

        _ ->
          result
      end
    else
      # Non-retryable error - don't retry
      throw({:non_retryable, result})
    end
  end

  defp execute_with_retry(retry_fun, retry_options, context) do
    try do
      case RetryUtils.run(retry_fun,
             max_attempts: Keyword.get(retry_options, :max_attempts, 3),
             base_backoff: Keyword.get(retry_options, :base_backoff, 1000),
             max_backoff: Keyword.get(retry_options, :max_backoff, 30_000),
             jitter: Keyword.get(retry_options, :jitter, true),
             retryable_errors:
               [:retryable_http_status, :http_error] ++ get_all_retryable_errors(retry_options),
             context: context,
             on_retry: &log_retry_attempt/3
           ) do
        {:ok, result} -> {:ok, result}
        {:error, {:retryable_http_status, response}} -> {:ok, response}
        {:error, reason} -> {:error, reason}
      end
    catch
      {:non_retryable, error} -> error
    end
  end

  defp get_retry_options(opts) do
    Keyword.get(opts, :retry_options, [])
  end

  defp build_context(request) do
    "HTTP #{String.upcase(to_string(request.method))} #{request.url}"
  end

  defp retryable_status_code?(status_code, retry_options) do
    retryable_codes =
      Keyword.get(retry_options, :retryable_status_codes, @default_retryable_status_codes)

    status_code in retryable_codes
  end

  defp retryable_error?(reason, retry_options) do
    retryable_errors = get_all_retryable_errors(retry_options)

    case reason do
      # HTTP errors with status codes
      {:http_error, status_code, _body} ->
        retryable_status_code?(status_code, retry_options)

      # Network/connection errors
      error when is_atom(error) ->
        error in retryable_errors

      # Tuple errors (e.g., {:timeout, details})
      {error, _details} when is_atom(error) ->
        error in retryable_errors

      # Other errors are not retryable by default
      _ ->
        false
    end
  end

  defp get_all_retryable_errors(retry_options) do
    custom_errors = Keyword.get(retry_options, :retryable_errors, [])

    (@default_retryable_errors ++ custom_errors)
    |> Enum.uniq()
  end

  defp log_retry_attempt(attempt, error, delay_ms) do
    Logger.info("HTTP request retry",
      attempt: attempt,
      error: format_error_for_log(error),
      delay_ms: delay_ms,
      middleware: "Retry",
      category: :api
    )
  end

  defp format_error_for_log({:http_error, status_code, _body}) do
    "HTTP #{status_code}"
  end

  defp format_error_for_log({:retryable_http_status, %{status_code: status_code}}) do
    "HTTP #{status_code}"
  end

  defp format_error_for_log(error) when is_atom(error) do
    to_string(error)
  end

  defp format_error_for_log({error, _details}) when is_atom(error) do
    to_string(error)
  end

  defp format_error_for_log(error) do
    inspect(error)
  end
end
