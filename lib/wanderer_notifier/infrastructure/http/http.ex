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
  alias WandererNotifier.Infrastructure.Http.Middleware.{Retry, RateLimiter}
  alias WandererNotifier.Shared.Utils.ErrorHandler

  @type url :: String.t()
  @type headers :: list({String.t(), String.t()})
  @type opts :: keyword()
  @type body :: String.t() | map() | nil
  @type method :: :get | :post | :put | :delete | :head | :options | :patch
  @type response ::
          {:ok, %{status_code: integer(), body: term(), headers: list()}} | {:error, term()}
  @type service :: :esi | :wanderer_kills | :license | :map | :streaming | nil

  # ══════════════════════════════════════════════════════════════════════════════
  # Core HTTP Interface
  # ══════════════════════════════════════════════════════════════════════════════

  @doc """
  Makes a generic HTTP request with retry logic and error handling.

  Simplified unified interface - all HTTP methods use this single function.

  ## Parameters
  - `method` - HTTP method (:get, :post, :put, :delete, :head, :options, :patch)
  - `url` - Target URL
  - `body` - Request body (nil for GET/DELETE, string/map for POST/PUT)
  - `headers` - List of {key, value} header tuples
  - `opts` - Request options (see below)

  ## Options
  - `:service` - Pre-configured service (:esi, :wanderer_kills, :license, :map, :streaming)
  - `:timeout` - Request timeout in milliseconds
  - `:retry_count` - Number of retries
  - `:decode_json` - Automatically decode JSON responses (default: true)
  - `:auth` - Authentication [type: :bearer, token: "..."] or [type: :api_key, key: "..."]

  ## Examples

      # Simple GET
      request(:get, "https://api.example.com/data", nil, [], [])
      
      # Service-configured request
      request(:get, url, nil, [], service: :esi)
      
      # POST with authentication
      request(:post, url, %{data: "value"}, [], service: :license, auth: [type: :bearer, token: token])
  """
  @spec request(method(), url(), body(), headers(), opts()) :: response()
  def request(method, url, body \\ nil, headers \\ [], opts \\ []) do
    # Apply service configuration
    final_opts = apply_service_config(opts)

    # Add authentication headers
    final_headers = apply_auth_headers(headers, final_opts)

    # Encode body if needed
    encoded_body = encode_body(body, final_headers)

    # Build client options and execute request
    client_opts = build_client_opts(final_opts, final_headers, encoded_body)

    # Make the request using the client
    Client.request(method, url, client_opts)
    |> transform_response()
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

  # Service configurations map
  @service_configs %{
    esi: [
      timeout: 30_000,
      retry_count: 3,
      retry_delay: 1_000,
      retryable_status_codes: [429, 500, 502, 503, 504],
      rate_limit: [requests_per_second: 20, burst_capacity: 40, per_host: true],
      middlewares: [Retry, RateLimiter],
      decode_json: true
    ],
    wanderer_kills: [
      timeout: 15_000,
      retry_count: 2,
      retry_delay: 1_000,
      retryable_status_codes: [429, 500, 502, 503, 504],
      rate_limit: [requests_per_second: 10, burst_capacity: 20, per_host: true],
      middlewares: [Retry, RateLimiter],
      decode_json: true
    ],
    license: [
      timeout: 10_000,
      retry_count: 1,
      retry_delay: 2_000,
      # Don't retry auth failures
      retryable_status_codes: [500, 502, 503, 504],
      rate_limit: [requests_per_second: 1, burst_capacity: 2, per_host: true],
      # No retry for license validation
      middlewares: [RateLimiter],
      decode_json: true
    ],
    map: [
      timeout: 60_000,
      retry_count: 2,
      retry_delay: 500,
      retryable_status_codes: [500, 502, 503, 504],
      # Internal service, no rate limiting
      disable_middleware: true,
      decode_json: true
    ],
    streaming: [
      timeout: :infinity,
      stream: true,
      retry_count: 0,
      disable_middleware: true,
      follow_redirects: false,
      decode_json: false
    ]
  }

  @doc false
  def service_config(service) when is_atom(service) do
    Map.get(@service_configs, service, [])
  end

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
    if body != nil, do: Keyword.put(client_opts, :body, body), else: client_opts
  end

  defp transform_response({:ok, response}) do
    {:ok, response}
  end

  defp transform_response({:error, {:http_error, status, body}}) do
    error = ErrorHandler.http_error_to_tuple(status)
    ErrorHandler.enrich_error(error, %{body: body})
  end

  defp transform_response({:error, reason}) do
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
    request(:get, url, nil, [], [])
  end

  @spec build_url(integer(), String.t()) :: String.t()
  defp build_url(killmail_id, hash) do
    "https://zkillboard.com/api/killID/#{killmail_id}/#{hash}/"
  end
end
