defmodule WandererNotifier.Infrastructure.Http.Client do
  @moduledoc """
  Unified HTTP client with middleware pipeline architecture.

  This module provides a single interface for making HTTP requests with
  configurable middleware chains. Middleware can handle cross-cutting concerns
  like retry logic, rate limiting, circuit breaking, and telemetry.

  ## Usage

      # Simple request
      Client.request(:get, "https://api.example.com/data")
      
      # Request with custom middleware
      Client.request(:get, "https://api.example.com/data", 
        middlewares: [RetryMiddleware, RateLimitMiddleware])
      
      # Request with options
      Client.request(:post, "https://api.example.com/data", 
        body: %{key: "value"},
        headers: [{"Authorization", "Bearer token"}],
        middlewares: [TelemetryMiddleware, RetryMiddleware])
  """

  alias WandererNotifier.Infrastructure.Http.Utils.JsonUtils
  alias WandererNotifier.Infrastructure.Http.Middleware.Telemetry
  alias WandererNotifier.Infrastructure.Http.Middleware.Retry

  # HTTP client configuration - use runtime config for test compatibility
  defp http_client do
    Application.get_env(:wanderer_notifier, :http_client, __MODULE__)
  end

  @type method :: :get | :post | :put | :delete | :head | :options | :patch
  @type url :: String.t()
  @type headers :: list({String.t(), String.t()})
  @type body :: String.t() | map() | nil
  @type opts :: keyword()
  @type middleware :: module()
  @type request :: %{
          method: method(),
          url: url(),
          headers: headers(),
          body: String.t() | nil,
          opts: opts()
        }
  @type response ::
          {:ok, %{status_code: integer(), body: term(), headers: list()}} | {:error, term()}

  @default_headers [{"Content-Type", "application/json"}]
  @default_get_headers []

  @doc """
  Makes an HTTP request with the specified method, URL and options.

  ## Options
  - `:body` - Request body (string, map, or nil)
  - `:headers` - Additional headers (list of tuples)
  - `:middlewares` - List of middleware modules to apply
  - `:timeout` - Request timeout in milliseconds
  - `:recv_timeout` - Receive timeout in milliseconds
  - `:connect_timeout` - Connection timeout in milliseconds
  - `:pool_timeout` - Pool timeout in milliseconds
  """
  @spec request(method(), url(), opts()) :: response()
  def request(method, url, opts \\ []) do
    # Prepare body and headers once to avoid duplication
    body = prepare_body(Keyword.get(opts, :body))
    headers = merge_headers(Keyword.get(opts, :headers, []), method)

    # Check if we're in test mode and using mock - delegate to WandererNotifier.HTTP for compatibility
    case http_client() do
      WandererNotifier.HTTPMock ->
        # Use the existing HTTP module which handles mocks properly
        WandererNotifier.HTTP.request(method, url, headers, body, opts)

      _ ->
        # Production mode - use middleware chain
        middlewares = Keyword.get(opts, :middlewares, default_middlewares())

        request = %{
          method: method,
          url: url,
          headers: headers,
          body: body,
          opts: opts
        }

        execute_middleware_chain(request, middlewares)
    end
  end

  @doc """
  Makes a GET request to the specified URL.
  """
  @spec get(url(), opts()) :: response()
  def get(url, opts \\ []) do
    request(:get, url, opts)
  end

  @doc """
  Makes a POST request with the given body.
  """
  @spec post(url(), body(), opts()) :: response()
  def post(url, body, opts \\ []) do
    opts_with_body = Keyword.put(opts, :body, body)
    request(:post, url, opts_with_body)
  end

  @doc """
  Makes a POST request with JSON body.
  """
  @spec post_json(url(), map(), opts()) :: response()
  def post_json(url, body, opts \\ []) when is_map(body) do
    post(url, body, opts)
  end

  @doc """
  Makes a PUT request with the given body.
  """
  @spec put(url(), body(), opts()) :: response()
  def put(url, body, opts \\ []) do
    opts_with_body = Keyword.put(opts, :body, body)
    request(:put, url, opts_with_body)
  end

  @doc """
  Makes a DELETE request.
  """
  @spec delete(url(), opts()) :: response()
  def delete(url, opts \\ []) do
    request(:delete, url, opts)
  end

  # Private functions

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
    # Use Req directly to avoid circular dependency
    req_opts = build_req_opts(opts, headers, body)

    case Req.request([method: method, url: url] ++ req_opts) do
      {:ok, %Req.Response{status: status, body: response_body, headers: response_headers}} ->
        {:ok, %{status_code: status, body: response_body, headers: response_headers}}

      {:error, reason} ->
        {:error, reason}
    end
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
      if Keyword.has_key?(opts, :connect_timeout),
        do: Keyword.put(req_opts, :connect_timeout, Keyword.get(opts, :connect_timeout)),
        else: req_opts

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

    base_headers ++ custom_headers
  end

  defp default_middlewares do
    # Default middleware chain with retry, rate limiting, and telemetry
    # Telemetry should be first to capture all metrics
    # Can be overridden per request
    [Telemetry, RateLimiter, Retry]
  end
end
