defmodule WandererNotifier.Infrastructure.Http do
  @behaviour WandererNotifier.Infrastructure.Http.Behaviour

  @moduledoc """
  Unified HTTP client module that handles all HTTP operations for the application.
  Provides a single interface for making HTTP requests with built-in retry logic,
  timeout management, error handling, and service-specific configurations.

  ## Service Configurations

  Pre-configured settings for external services:
  - `:esi` - EVE Online ESI API with rate limiting and retry logic
  - `:wanderer_kills` - WandererKills API with moderate rate limits
  - `:license` - License validation API with conservative limits
  - `:janice` - Janice price evaluation API with moderate rate limits
  - `:map` - Internal map API with extended timeouts
  - `:streaming` - Special configuration for streaming endpoints
  - `:fuzzworks` - Fuzzworks data dump API for static EVE data

  ## Usage Examples

      # Simple GET request
      Http.request(:get, "https://api.example.com/data")

      # Service-specific request with pre-configured settings
      Http.request(:get, url, nil, [], service: :esi)

      # Custom configuration
      Http.request(:get, url, nil, [], timeout: 45_000, retry_count: 3)

      # POST with authentication
      Http.request(:post, url, body, [], service: :license, auth: [type: :bearer, token: token])
  """

  alias WandererNotifier.Infrastructure.Http.Utils.JsonUtils

  alias WandererNotifier.Infrastructure.Http.Middleware.{
    Telemetry,
    Retry,
    RateLimiter,
    DynamicRateLimiter
  }

  alias WandererNotifier.Shared.Utils.ErrorHandler
  require Logger

  @type url :: String.t()
  @type headers :: list({String.t(), String.t()})
  @type opts :: keyword()
  @type body :: String.t() | map() | nil
  @type method :: :get | :post | :put | :delete | :head | :options | :patch
  @type response ::
          {:ok, %{status_code: integer(), body: term(), headers: list()}} | {:error, term()}
  @type service ::
          :esi
          | :wanderer_kills
          | :license
          | :janice
          | :map
          | :discord
          | :streaming
          | :fuzzworks
          | nil
  @type middleware :: module()
  @type request :: %{
          method: method(),
          url: url(),
          headers: headers(),
          body: String.t() | nil,
          opts: opts()
        }

  # HTTP client configuration - use runtime config for test compatibility
  defp http_client do
    Application.get_env(:wanderer_notifier, :http_client, __MODULE__)
  end

  @default_headers [{"Content-Type", "application/json"}]
  @default_get_headers []

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
  - `:service` - Pre-configured service (:esi, :wanderer_kills, :license, :map, :discord, :streaming, :fuzzworks)
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
  @impl true
  @spec request(method(), url(), body(), headers(), opts()) :: response()
  def request(method, url, body \\ nil, headers \\ [], opts \\ []) do
    case http_client() do
      WandererNotifier.HTTPMock ->
        make_mock_request(method, url, body, headers, opts)

      _ ->
        make_real_request(method, url, body, headers, opts)
    end
  end

  defp make_mock_request(method, url, body, headers, opts) do
    final_opts = apply_service_config(opts)

    # Add Content-Type header for JSON if needed
    headers_with_json = add_json_content_type_if_needed(body, headers, method)

    # Apply auth headers and encode body
    final_headers = apply_auth_headers(headers_with_json, final_opts)
    encoded_body = encode_body(body, final_headers)

    # Call appropriate mock method
    call_mock_method(method, url, encoded_body, final_headers, final_opts)
  end

  defp add_json_content_type_if_needed(body, headers, method) do
    if is_map(body) and not has_content_type?(headers) and method in [:post, :put, :patch] do
      [{"Content-Type", "application/json"} | headers]
    else
      headers
    end
  end

  defp call_mock_method(method, url, encoded_body, final_headers, final_opts) do
    # Call the mock's request/5 method directly
    http_client().request(method, url, encoded_body, final_headers, final_opts)
  end

  defp make_real_request(method, url, body, headers, opts) do
    # Production mode - apply service configuration
    final_opts = apply_service_config(opts)

    # Add authentication headers
    final_headers = apply_auth_headers(headers, final_opts)

    # Encode body if needed
    encoded_body = encode_body(body, final_headers)

    # Prepare body and headers for middleware chain
    prepared_body = prepare_body(encoded_body)
    merged_headers = merge_headers(final_headers, method)

    # Get middlewares from options or use defaults
    middlewares = Keyword.get(final_opts, :middlewares, default_middlewares())

    # Create request struct for middleware chain
    request = %{
      method: method,
      url: url,
      headers: merged_headers,
      body: prepared_body,
      opts: final_opts
    }

    # Execute middleware chain
    execute_middleware_chain(request, middlewares)
    |> transform_response()
  end

  # Private implementation

  # Middleware chain execution from Client module
  defp execute_middleware_chain(request, []) do
    # No middleware - execute the actual HTTP request
    make_http_request(request)
  end

  defp execute_middleware_chain(request, [middleware | remaining_middlewares]) do
    next_fun = fn req ->
      execute_middleware_chain(req, remaining_middlewares)
    end

    middleware.call(request, next_fun)
  end

  defp make_http_request(%{method: method, url: url, headers: headers, body: body, opts: opts}) do
    req_opts = build_req_opts(opts, headers, body)
    start_time = System.monotonic_time(:millisecond)

    log_license_request_if_needed(url, method, headers, body, opts)
    Logger.debug("Starting HTTP request: #{method} #{url}")

    case Req.request([method: method, url: url] ++ req_opts) do
      {:ok, response} ->
        handle_successful_response(response, start_time, method, url)

      {:error, reason} ->
        handle_failed_response(reason, start_time, method, url)
    end
  end

  defp log_license_request_if_needed(url, method, headers, body, opts) do
    if String.contains?(url, "validate_bot") do
      Logger.info("License HTTP request details",
        method: method,
        url: url,
        headers: sanitize_headers(headers),
        body_keys: if(is_map(body), do: Map.keys(body), else: "not_a_map"),
        service: Keyword.get(opts, :service),
        category: :api
      )
    end
  end

  defp sanitize_headers(headers) do
    Enum.map(headers, fn {k, v} ->
      if k == "authorization", do: {k, "[REDACTED]"}, else: {k, v}
    end)
  end

  defp handle_successful_response(
         %Req.Response{status: status, body: response_body, headers: response_headers},
         start_time,
         method,
         url
       ) do
    duration = System.monotonic_time(:millisecond) - start_time
    Logger.debug("HTTP request completed in #{duration}ms: #{method} #{url}")
    {:ok, %{status_code: status, body: response_body, headers: response_headers}}
  end

  defp handle_failed_response(reason, start_time, method, url) do
    duration = System.monotonic_time(:millisecond) - start_time

    Logger.warning(
      "HTTP request failed after #{duration}ms: #{method} #{url} - #{inspect(reason)}"
    )

    {:error, reason}
  end

  defp build_req_opts(opts, headers, body) do
    req_opts = []

    # Add headers if provided
    req_opts = if headers != [], do: Keyword.put(req_opts, :headers, headers), else: req_opts

    # Add body if provided
    req_opts = if body != nil, do: Keyword.put(req_opts, :body, body), else: req_opts

    # Add timeout options - prioritize recv_timeout over timeout if both are present
    receive_timeout =
      cond do
        Keyword.has_key?(opts, :recv_timeout) -> Keyword.get(opts, :recv_timeout)
        Keyword.has_key?(opts, :timeout) -> Keyword.get(opts, :timeout)
        true -> nil
      end

    req_opts =
      if receive_timeout,
        do: Keyword.put(req_opts, :receive_timeout, receive_timeout),
        else: req_opts

    req_opts =
      if Keyword.has_key?(opts, :connect_timeout) do
        connect_timeout = Keyword.get(opts, :connect_timeout)
        Keyword.put(req_opts, :connect_options, timeout: connect_timeout)
      else
        req_opts
      end

    req_opts
  end

  defp prepare_body(nil), do: nil
  defp prepare_body(body) when is_binary(body), do: body

  defp prepare_body(body) when is_map(body) do
    case JsonUtils.encode(body) do
      {:ok, encoded} ->
        encoded

      {:error, reason} ->
        raise ArgumentError, "Failed to encode body to JSON: #{inspect(reason)}"
    end
  end

  defp prepare_body(body), do: to_string(body)

  defp merge_headers(custom_headers, method) do
    base_headers =
      if method in [:get, :head, :delete], do: @default_get_headers, else: @default_headers

    # Ensure custom_headers is a list
    safe_headers = custom_headers || []

    # If custom headers already have Content-Type, don't add the default one
    if has_content_type?(safe_headers) do
      safe_headers
    else
      base_headers ++ safe_headers
    end
  end

  defp default_middlewares do
    # Default middleware chain with retry, rate limiting, and telemetry
    # Telemetry should be first to capture all metrics
    # Can be overridden per request
    [Telemetry, RateLimiter, Retry]
  end

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
    # Ensure no duplicate keys before merging
    service_opts = Keyword.delete(service_opts, :service)
    opts = Keyword.delete(opts, :service)
    Keyword.merge(service_opts, opts)
  end

  # Service configurations map
  @service_configs %{
    esi: [
      # ESI typically responds in 80-240ms, 3s timeout is plenty
      timeout: 3_000,
      retry_count: 3,
      retry_delay: 500,
      retryable_status_codes: [429, 500, 502, 503, 504],
      # Use dynamic rate limiting based on X-ESI-Error-Limit-* headers
      middlewares: [Retry, DynamicRateLimiter],
      decode_json: true
    ],
    wanderer_kills: [
      # WandererKills is fast, 5s timeout is generous
      timeout: 5_000,
      retry_count: 2,
      retry_delay: 500,
      retryable_status_codes: [429, 500, 502, 503, 504],
      rate_limit: [requests_per_second: 10, burst_capacity: 20, per_host: true],
      middlewares: [Retry, RateLimiter],
      decode_json: true
    ],
    license: [
      # License validation typically 300-400ms
      timeout: 3_000,
      retry_count: 2,
      retry_delay: 1_000,
      # Don't retry auth failures
      retryable_status_codes: [500, 502, 503, 504],
      rate_limit: [requests_per_second: 1, burst_capacity: 2, per_host: true],
      middlewares: [Retry, RateLimiter],
      decode_json: true
    ],
    janice: [
      # Janice usually responds in 500ms, but can be slow
      timeout: 5_000,
      retry_count: 3,
      retry_delay: 500,
      retryable_status_codes: [429, 500, 502, 503, 504],
      rate_limit: [requests_per_second: 5, burst_capacity: 10, per_host: true],
      middlewares: [Retry, RateLimiter],
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
    discord: [
      # Discord API typically responds in 200-500ms
      timeout: 10_000,
      retry_count: 3,
      retry_delay: 1_000,
      retryable_status_codes: [429, 500, 502, 503, 504],
      # Use dynamic rate limiting based on X-RateLimit-* headers with webhook and global limits
      middlewares: [Retry, DynamicRateLimiter],
      decode_json: true
    ],
    streaming: [
      timeout: :infinity,
      stream: true,
      retry_count: 0,
      disable_middleware: true,
      follow_redirects: false,
      decode_json: false
    ],
    fuzzworks: [
      timeout: 60_000,
      retry_count: 2,
      retry_delay: 2_000,
      retryable_status_codes: [429, 500, 502, 503, 504],
      rate_limit: [
        service: :fuzzworks,
        requests_per_second: 5,
        burst_capacity: 10,
        per_host: true
      ],
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

  defp has_content_type?(nil), do: false

  defp has_content_type?(headers) when is_list(headers) do
    Enum.any?(headers, fn
      {"Content-Type", _} -> true
      _ -> false
    end)
  end

  defp has_content_type?(_), do: false

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
  Makes a GET request with JSON decoding enabled.

  ## Parameters
    - url: The URL to request
    - headers: Optional headers (defaults to [])
    - opts: Optional configuration (defaults to [])

  ## Returns
    - {:ok, response} on success with JSON-decoded body
    - {:error, reason} on failure
  """
  @spec get_json(url(), headers(), opts()) :: response()
  def get_json(url, headers \\ [], opts \\ []) do
    json_opts = Keyword.put(opts, :decode_json, true)
    request(:get, url, nil, headers, json_opts)
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

  # ══════════════════════════════════════════════════════════════════════════════
  # Service-Specific Convenience Methods
  # ══════════════════════════════════════════════════════════════════════════════

  @doc """
  Makes a GET request to the ESI API.

  ## Parameters
    - url: The ESI endpoint URL
    - headers: Optional headers (defaults to [])
    - opts: Additional options
  """
  @spec esi_get(url(), headers(), opts()) :: response()
  def esi_get(url, headers \\ [], opts \\ []) do
    request(:get, url, nil, headers, Keyword.put(opts, :service, :esi))
  end

  @doc """
  Makes a GET request to WandererKills API with default headers.

  ## Parameters
    - url: The WandererKills endpoint URL
    - headers: Optional headers (defaults to [])
    - opts: Additional options
  """
  @spec wanderer_kills_get(url(), headers(), opts()) :: response()
  def wanderer_kills_get(url, headers \\ [], opts \\ []) do
    request(:get, url, nil, headers, Keyword.put(opts, :service, :wanderer_kills))
  end

  @doc """
  Makes a POST request to WandererKills API with JSON body.

  ## Parameters
    - url: The WandererKills endpoint URL
    - body: Request body (will be JSON encoded if map)
    - headers: Optional headers (defaults to [])
    - opts: Additional options
  """
  @spec wanderer_kills_post(url(), body(), headers(), opts()) :: response()
  def wanderer_kills_post(url, body, headers \\ [], opts \\ []) do
    request(:post, url, body, headers, Keyword.put(opts, :service, :wanderer_kills))
  end

  @doc """
  Makes a GET request to the Map API.

  ## Parameters
    - url: The Map API endpoint URL
    - headers: Optional headers (defaults to [])
    - opts: Additional options
  """
  @spec map_get(url(), headers(), opts()) :: response()
  def map_get(url, headers \\ [], opts \\ []) do
    request(:get, url, nil, headers, Keyword.put(opts, :service, :map))
  end

  @doc """
  Makes a POST request to the License API with authentication.

  ## Parameters
    - url: The License API endpoint URL
    - body: Request body
    - token: Bearer token for authentication
    - headers: Optional headers (defaults to [])
    - opts: Additional options
  """
  @spec license_post(url(), body(), String.t(), headers(), opts()) :: response()
  def license_post(url, body, token, headers \\ [], opts \\ []) do
    auth_opts = [service: :license, auth: [type: :bearer, token: token]]
    final_opts = Keyword.merge(opts, auth_opts)
    request(:post, url, body, headers, final_opts)
  end

  @doc """
  Makes a POST request to Discord API.

  ## Parameters
    - url: The Discord API endpoint URL
    - body: Request body
    - headers: Optional headers (defaults to [])
    - opts: Additional options
  """
  @spec discord_post(url(), body(), headers(), opts()) :: response()
  def discord_post(url, body, headers \\ [], opts \\ []) do
    request(:post, url, body, headers, Keyword.put(opts, :service, :discord))
  end

  @doc """
  Makes a GET request to Fuzzworks API with extended timeout.

  ## Parameters
    - url: The Fuzzworks endpoint URL
    - headers: Optional headers (defaults to [])
    - opts: Additional options
  """
  @spec fuzzworks_get(url(), headers(), opts()) :: response()
  def fuzzworks_get(url, headers \\ [], opts \\ []) do
    request(:get, url, nil, headers, Keyword.put(opts, :service, :fuzzworks))
  end
end
