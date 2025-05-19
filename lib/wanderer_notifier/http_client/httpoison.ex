defmodule WandererNotifier.HttpClient.Httpoison do
  @moduledoc """
  HTTPoison implementation of the HTTP client behavior
  """
  @behaviour WandererNotifier.HttpClient.Behaviour

  alias WandererNotifier.Logger.Logger, as: AppLogger

  @default_headers [{"Content-Type", "application/json"}]

  @callback get(url :: String.t(), headers :: list(), options :: keyword()) ::
              {:ok, map()} | {:error, any()}

  @impl true
  def get(url, headers \\ @default_headers) do
    url
    |> HTTPoison.get(headers)
    |> handle_response()
  end

  @impl true
  def get(url, headers, options) do
    url
    |> HTTPoison.get(headers, options)
    |> handle_response()
  end

  @impl true
  def post(url, body, headers \\ @default_headers) do
    url
    |> HTTPoison.post(body, headers)
    |> handle_response()
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

    url
    |> HTTPoison.post(encoded_body, headers, options)
    |> handle_response()
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

    url
    |> HTTPoison.request(method, payload, headers, opts)
    |> handle_response()
  end

  @impl true
  def handle_response(
        {:ok, %HTTPoison.Response{status_code: status, body: body, headers: _headers}}
      )
      when status in 200..299 do
    # Special handling for license validation with empty response
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

  # Special handling for 429 Too Many Requests response
  def handle_response(
        {:ok, %HTTPoison.Response{status_code: 429, body: _body, headers: _headers}}
      ) do
    AppLogger.api_warn("License server rate limit exceeded (429 Too Many Requests)")
    {:error, :rate_limited}
  end

  def handle_response(
        {:ok, %HTTPoison.Response{status_code: status, body: body, headers: headers}}
      ) do
    AppLogger.error("HTTP client non-2xx response",
      status: status,
      body_preview: String.slice("#{body}", 0, 500),
      headers: inspect(headers)
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

  def handle_response({:error, %HTTPoison.Error{reason: reason}}) do
    AppLogger.error("HTTP request failed",
      error: inspect(reason)
    )

    {:error, reason}
  end

  def handle_response(other) do
    {:error, {:unexpected_response, other}}
  end
end
