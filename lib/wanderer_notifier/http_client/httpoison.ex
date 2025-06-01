defmodule WandererNotifier.HttpClient.Httpoison do
  @moduledoc """
  HTTPoison implementation of the HTTP client behavior
  """
  @behaviour WandererNotifier.HttpClient.Behaviour

  alias WandererNotifier.Logger.Logger, as: AppLogger
  alias WandererNotifier.Constants
  alias WandererNotifier.Utils.Retry

  @default_headers [{"Content-Type", "application/json"}]

  defp default_opts do
    [
      timeout: Constants.default_timeout(),
      recv_timeout: Constants.default_recv_timeout(),
      connect_timeout: Constants.default_connect_timeout(),
      pool_timeout: Constants.default_pool_timeout(),
      hackney: [pool: :default]
    ]
  end

  defp merge_opts(opts) do
    Keyword.merge(default_opts(), opts)
  end

  @callback get(url :: String.t(), headers :: list(), options :: keyword()) ::
              {:ok, map()} | {:error, any()}

  @impl true
  def get(url, headers \\ @default_headers) do
    get(url, headers, [])
  end

  @impl true
  def get(url, headers, options) do
    Retry.http_retry(fn ->
      url
      |> HTTPoison.get(headers, merge_opts(options))
      |> handle_response_with_context(url, "GET")
    end)
  end

  @impl true
  def post(url, body, headers \\ @default_headers) do
    post(url, body, headers, [])
  end

  @impl true
  def post(url, body, headers, options) do
    Retry.http_retry(fn ->
      url
      |> HTTPoison.post(body, headers, merge_opts(options))
      |> handle_response_with_context(url, "POST")
    end)
  end

  @impl true
  def post_json(url, body, headers \\ @default_headers, options \\ []) do
    encoded_body = Jason.encode!(body)

    # Add detailed debug logging for license validation requests
    if String.contains?(url, "validate_bot") || String.contains?(url, "validate_license") do
      AppLogger.api_debug("License validation request",
        url: url,
        body: encoded_body,
        headers: inspect(headers),
        options: inspect(options)
      )
    end

    Retry.http_retry(fn ->
      url
      |> HTTPoison.post(encoded_body, headers, merge_opts(options))
      |> handle_response_with_context(url, "POST")
    end)
  end

  @doc """
  Makes a generic HTTP request
  """
  @impl true
  def request(method, url, headers \\ [], body \\ nil, opts \\ []) do
    payload =
      case body do
        nil -> ""
        body when is_map(body) -> Jason.encode!(body)
        body -> body
      end

    Retry.http_retry(fn ->
      url
      |> HTTPoison.request(method, payload, headers, merge_opts(opts))
      |> handle_response_with_context(url, method)
    end)
  end

  # Private helper with context for better error reporting
  defp handle_response_with_context(response, url, method) do
    case response do
      {:ok, %HTTPoison.Response{status_code: status, body: _body, headers: _headers}}
      when status in 200..299 ->
        handle_response(response)

      {:ok, %HTTPoison.Response{status_code: 429, body: _body, headers: _headers}} ->
        handle_rate_limit_response(url, method)

      {:ok, %HTTPoison.Response{status_code: status, body: body, headers: _headers}} ->
        handle_error_response(url, method, status, body)

      {:error, %HTTPoison.Error{reason: reason}} ->
        handle_httpoison_error(url, method, reason)

      other ->
        handle_unexpected_response(url, method, other)
    end
  end

  defp handle_rate_limit_response(url, method) do
    AppLogger.api_warn("HTTP rate limit exceeded: #{method} #{url} (429 Too Many Requests)")
    {:error, :rate_limited}
  end

  defp handle_error_response(url, method, status, body) do
    AppLogger.error("HTTP client non-2xx response: #{method} #{url} - Status #{status}")

    # For HTTP errors, attempt to parse the body as JSON for more detailed error info
    decoded_body = decode_response_body(body)

    # Keep the original response format expected by callers
    {:ok, %{status_code: status, body: decoded_body}}
  end

  defp handle_httpoison_error(url, method, reason) do
    AppLogger.error("HTTP request failed: #{method} #{url} - #{inspect(reason)}")
    {:error, reason}
  end

  defp handle_unexpected_response(url, method, other) do
    AppLogger.error("Unexpected HTTP response: #{method} #{url} - #{inspect(other)}")
    {:error, {:unexpected_response, other}}
  end

  defp decode_response_body(body) do
    case Jason.decode(body) do
      {:ok, json} -> json
      _ -> body
    end
  end

  @impl true
  def handle_response(
        {:ok, %HTTPoison.Response{status_code: status, body: body, headers: _headers}}
      )
      when status in 200..299 do
    if String.trim(body) == "" do
      AppLogger.api_debug("Empty response body from HTTP request")

      # Just return the empty body
      {:ok, %{status_code: status, body: body}}
    else
      # Add detailed debug logging for license validation responses
      if String.length(body) < 100 do
        AppLogger.api_debug("Raw HTTP response body", body: inspect(body))
      end

      case Jason.decode(body) do
        {:ok, decoded} ->
          # Log the decoded response for debugging
          # AppLogger.info("HTTP request successful, decoded body: #{inspect(decoded, limit: 1000)}")
          {:ok, %{status_code: status, body: decoded}}

        {:error, reason} ->
          # Return the raw body if it can't be decoded as JSON
          AppLogger.api_debug("Failed to decode JSON response",
            reason: inspect(reason),
            body: inspect(body)
          )

          {:ok, %{status_code: status, body: body}}
      end
    end
  end

  # Fallback for public interface - non-2xx responses
  def handle_response(
        {:ok, %HTTPoison.Response{status_code: status, body: body, headers: _headers}}
      ) do
    AppLogger.error(
      "HTTP client non-2xx response (fallback path - missing context): Status #{status}"
    )

    # For HTTP errors, attempt to parse the body as JSON for more detailed error info
    decoded_body =
      case Jason.decode(body) do
        {:ok, json} -> json
        _ -> body
      end

    # Keep the original response format expected by callers
    {:ok, %{status_code: status, body: decoded_body}}
  end

  # Fallback for public interface - errors
  def handle_response({:error, reason}) do
    AppLogger.error("HTTP request failed (fallback path - missing context): #{inspect(reason)}")

    {:error, reason}
  end

  def handle_response(other) do
    AppLogger.error(
      "Unexpected HTTP response (fallback path - missing context): #{inspect(other)}"
    )

    {:error, {:unexpected_response, other}}
  end
end
