defmodule WandererNotifier.Infrastructure.Http do
  @moduledoc """
  Unified HTTP client module that handles all HTTP operations for the application.
  Provides a single interface for making HTTP requests with built-in retry logic,
  timeout management, error handling, and service-specific configurations.

  ## Service Configurations

  Pre-configured settings for external services:
  - `:esi` - EVE Online ESI API with rate limiting and retry logic
  - `:wanderer_kills` - WandererKills API with moderate rate limits
  - `:license` - License validation API with conservative limits
  - `:map` - Internal map API with extended timeouts
  - `:streaming` - Special configuration for streaming endpoints

  ## Usage Examples

      # Simple GET request
      Http.get("https://api.example.com/data")
      
      # Service-specific request with pre-configured settings
      Http.get(url, [], service: :esi)
      
      # Custom configuration
      Http.get(url, [], timeout: 45_000, retry_count: 3)
      
      # POST with authentication
      Http.post(url, body, [], service: :license, auth: [type: :bearer, token: token])
  """
  @behaviour WandererNotifier.Infrastructure.Http.HttpBehaviour

  alias WandererNotifier.Infrastructure.Http.Client
  alias WandererNotifier.Infrastructure.Http.Middleware.{Retry, RateLimiter, CircuitBreaker}
  alias WandererNotifier.Shared.Utils.ErrorHandler

  @type url :: String.t()
  @type headers :: list({String.t(), String.t()})
  @type opts :: keyword()
  @type body :: String.t() | map() | nil
  @type method :: :get | :post | :put | :delete | :head | :options | :patch
  @type response ::
          {:ok, %{status_code: integer(), body: term(), headers: list()}} | {:error, term()}
  @type service :: :esi | :wanderer_kills | :license | :map | :streaming | nil

  @doc """
  Makes a GET request to the specified URL.
  """
  @spec get(url(), headers(), opts()) :: response()
  def get(url, headers \\ [], opts \\ []) do
    request(:get, url, headers, nil, opts)
  end

  @doc """
  Makes a POST request with the given body.
  """
  @spec post(url(), body(), headers(), opts()) :: response()
  def post(url, body, headers \\ [{"Content-Type", "application/json"}], opts \\ []) do
    request(:post, url, headers, body, opts)
  end

  @doc """
  Makes a POST request with JSON body.
  """
  @spec post_json(url(), map(), headers(), opts()) :: response()
  def post_json(url, body, headers \\ [{"Content-Type", "application/json"}], opts \\ []) do
    post(url, body, headers, opts)
  end

  @doc """
  Makes a PUT request with the given body.
  """
  @spec put(url(), body(), headers(), opts()) :: response()
  def put(url, body, headers \\ [{"Content-Type", "application/json"}], opts \\ []) do
    request(:put, url, headers, body, opts)
  end

  @doc """
  Makes a DELETE request.
  """
  @spec delete(url(), headers(), opts()) :: response()
  def delete(url, headers \\ [], opts \\ []) do
    request(:delete, url, headers, nil, opts)
  end

  @doc """
  Makes a PATCH request with the given body.
  """
  @spec patch(url(), body(), headers(), opts()) :: response()
  def patch(url, body, headers \\ [{"Content-Type", "application/json"}], opts \\ []) do
    request(:patch, url, headers, body, opts)
  end

  @doc """
  Makes a HEAD request.
  """
  @spec head(url(), headers(), opts()) :: response()
  def head(url, headers \\ [], opts \\ []) do
    request(:head, url, headers, nil, opts)
  end

  @doc """
  Makes a GET request with automatic JSON decoding.
  """
  @spec get_json(url(), headers(), opts()) :: response()
  def get_json(url, headers \\ [], opts \\ []) do
    opts_with_json = Keyword.put(opts, :decode_json, true)
    get(url, headers, opts_with_json)
  end

  @doc """
  Makes a generic HTTP request with retry logic and error handling.
  Supports service-specific configurations and custom options.

  ## Options
  - `:service` - Pre-configured service settings (:esi, :wanderer_kills, :license, :map, :streaming)
  - `:timeout` - Request timeout in milliseconds
  - `:retry_count` - Number of retries
  - `:retry_delay` - Base delay between retries
  - `:decode_json` - Automatically decode JSON responses
  - `:auth` - Authentication options [type: :bearer, token: "..."]
  - `:rate_limit` - Rate limiting options [requests_per_second: 10, burst_capacity: 20]
  - `:middlewares` - Custom middleware chain
  - `:disable_middleware` - Bypass all middleware
  """
  @spec request(method(), url(), headers(), body(), opts()) :: response()
  def request(method, url, headers, body, opts) do
    # Apply service configuration if specified
    enhanced_opts = apply_service_config(opts)

    # Apply authentication if specified
    enhanced_headers = apply_auth_headers(headers, enhanced_opts)

    # Check if we're in test mode and using mock
    case Application.get_env(:wanderer_notifier, :http_client) do
      WandererNotifier.HTTPMock ->
        # Use the mock directly for testing
        mock = WandererNotifier.HTTPMock

        case method do
          :get ->
            apply(mock, :get, [url, enhanced_headers, enhanced_opts])

          :post ->
            encoded_body = encode_body(body, enhanced_headers)
            apply(mock, :post, [url, encoded_body, enhanced_headers, enhanced_opts])

          :put ->
            encoded_body = encode_body(body, enhanced_headers)
            apply(mock, :put, [url, encoded_body, enhanced_headers, enhanced_opts])

          :delete ->
            apply(mock, :delete, [url, enhanced_headers, enhanced_opts])

          _ ->
            {:error, :method_not_supported}
        end

      _ ->
        # Production mode - use the new middleware-based client
        client_opts = build_client_opts(enhanced_opts, enhanced_headers, body)
        result = Client.request(method, url, client_opts)
        transform_response(result)
    end
  end

  # Private implementation

  @doc false
  def apply_service_config(opts) do
    case Keyword.get(opts, :service) do
      nil -> opts
      service -> merge_service_config(opts, service_config(service))
    end
  end

  @doc false
  def apply_auth_headers(headers, opts) do
    case Keyword.get(opts, :auth) do
      nil -> headers
      auth_config -> add_auth_header(headers, auth_config)
    end
  end

  defp merge_service_config(opts, service_opts) do
    # Service config has lower priority than explicit opts
    Keyword.merge(service_opts, opts)
  end

  @doc false
  def service_config(:esi) do
    [
      timeout: 30_000,
      retry_count: 3,
      retry_delay: 1_000,
      retryable_status_codes: [429, 500, 502, 503, 504],
      rate_limit: [requests_per_second: 20, burst_capacity: 40, per_host: true],
      middlewares: [Retry, RateLimiter],
      decode_json: true,
      telemetry_metadata: %{service: "esi"}
    ]
  end

  def service_config(:wanderer_kills) do
    [
      timeout: 15_000,
      retry_count: 2,
      retry_delay: 1_000,
      retryable_status_codes: [429, 500, 502, 503, 504],
      rate_limit: [requests_per_second: 10, burst_capacity: 20, per_host: true],
      middlewares: [Retry, RateLimiter],
      decode_json: true,
      telemetry_metadata: %{service: "wanderer_kills"}
    ]
  end

  def service_config(:license) do
    [
      timeout: 10_000,
      retry_count: 1,
      retry_delay: 2_000,
      # Don't retry auth failures
      retryable_status_codes: [500, 502, 503, 504],
      rate_limit: [requests_per_second: 1, burst_capacity: 2, per_host: true],
      # No retry for license validation
      middlewares: [RateLimiter],
      decode_json: true,
      telemetry_metadata: %{service: "license"}
    ]
  end

  def service_config(:map) do
    [
      timeout: 60_000,
      retry_count: 2,
      retry_delay: 500,
      retryable_status_codes: [500, 502, 503, 504],
      # Internal service, no rate limiting
      disable_middleware: true,
      decode_json: true,
      telemetry_metadata: %{service: "map"}
    ]
  end

  def service_config(:streaming) do
    [
      timeout: :infinity,
      stream: true,
      retry_count: 0,
      disable_middleware: true,
      follow_redirects: false,
      decode_json: false,
      telemetry_metadata: %{service: "streaming"}
    ]
  end

  def service_config(_unknown), do: []

  defp add_auth_header(headers, type: :bearer, token: token) when is_binary(token) do
    [{"Authorization", "Bearer #{token}"} | headers]
  end

  defp add_auth_header(headers, type: :bearer), do: headers

  defp add_auth_header(headers, type: :api_key, key: key) when is_binary(key) do
    [{"X-API-Key", key} | headers]
  end

  defp add_auth_header(headers, type: :api_key), do: headers

  defp add_auth_header(headers, type: :basic, username: username, password: password) do
    credentials = Base.encode64("#{username}:#{password}")
    [{"Authorization", "Basic #{credentials}"} | headers]
  end

  defp add_auth_header(headers, _invalid_auth), do: headers

  defp encode_body(body, headers) when is_map(body) do
    if has_json_content_type?(headers) do
      Jason.encode!(body)
    else
      body
    end
  end

  defp encode_body(body, _headers), do: body

  defp has_json_content_type?(headers) do
    Enum.any?(headers, fn
      {"Content-Type", content_type} -> String.contains?(content_type, "json")
      _ -> false
    end)
  end

  defp build_client_opts(opts, headers, body) do
    # Start with the provided options
    client_opts = opts

    # Add headers if provided
    client_opts =
      if headers != [], do: Keyword.put(client_opts, :headers, headers), else: client_opts

    # Add body if provided
    client_opts = if body != nil, do: Keyword.put(client_opts, :body, body), else: client_opts

    # Configure middleware chain based on options
    middlewares = configure_middlewares(opts)

    if middlewares != [] do
      Keyword.put(client_opts, :middlewares, middlewares)
    else
      client_opts
    end
  end

  defp configure_middlewares(opts) do
    # Check if middleware was explicitly disabled
    if Keyword.get(opts, :middlewares) == [] do
      # Explicit bypass - no middleware at all
      []
    else
      middlewares = []

      # Add retry middleware if retry options are present
      middlewares =
        if Keyword.has_key?(opts, :retry_options) do
          [Retry | middlewares]
        else
          middlewares
        end

      # Add rate limiter middleware if rate limit options are present
      middlewares =
        if Keyword.has_key?(opts, :rate_limit_options) do
          [RateLimiter | middlewares]
        else
          middlewares
        end

      # Add circuit breaker middleware if circuit breaker options are present
      middlewares =
        if Keyword.has_key?(opts, :circuit_breaker_options) do
          [CircuitBreaker | middlewares]
        else
          middlewares
        end

      # If no specific middleware configured, use default chain
      if middlewares == [] do
        # Default middleware chain (telemetry is included by default in Client)
        [Retry, RateLimiter]
      else
        middlewares
      end
    end
  end

  defp transform_response({:ok, response}) do
    # Response is already in the correct format from the new client
    {:ok, response}
  end

  defp transform_response({:error, {:http_error, status, body}}) do
    # Transform HTTP errors to standardized format
    error = ErrorHandler.http_error_to_tuple(status)
    ErrorHandler.enrich_error(error, %{body: body})
  end

  defp transform_response({:error, reason}) do
    # Normalize other errors
    ErrorHandler.normalize_error({:error, reason})
  end

  @doc """
  Makes a GET request to the ZKill API for a specific killmail.
  Requires both the killmail ID and hash for proper identification.

  ## Parameters
    - killmail_id: The ID of the killmail
    - hash: The hash of the killmail

  ## Returns
    - {:ok, response} on success
    - {:error, reason} on failure
  """
  @spec get_killmail(integer(), String.t()) :: response()
  def get_killmail(killmail_id, hash) do
    url = build_url(killmail_id, hash)
    get(url)
  end

  @spec build_url(integer(), String.t()) :: String.t()
  defp build_url(killmail_id, hash) do
    "https://zkillboard.com/api/killID/#{killmail_id}/#{hash}/"
  end
end
