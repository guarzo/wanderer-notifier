defmodule WandererNotifier.HTTP do
  @moduledoc """
  Unified HTTP client module that handles all HTTP operations for the application.
  Provides a single interface for making HTTP requests with built-in retry logic,
  timeout management, and error handling.
  """
  @behaviour WandererNotifier.HTTP.HttpBehaviour

  alias WandererNotifier.Http.Client
  alias WandererNotifier.Http.Middleware.{Retry, RateLimiter, CircuitBreaker}

  @type url :: String.t()
  @type headers :: list({String.t(), String.t()})
  @type opts :: keyword()
  @type body :: String.t() | map()
  @type method :: :get | :post | :put | :delete | :head | :options
  @type response :: {:ok, %{status_code: integer(), body: term()}} | {:error, term()}

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
  Makes a generic HTTP request with retry logic and error handling.
  """
  @spec request(method(), url(), headers(), body() | nil, opts()) :: response()
  def request(method, url, headers, body, opts) do
    # Check if we're in test mode and using mock
    case Application.get_env(:wanderer_notifier, :http_client) do
      WandererNotifier.HTTPMock ->
        # Use the mock directly for testing
        mock = WandererNotifier.HTTPMock

        case method do
          :get ->
            apply(mock, :get, [url, headers, opts])

          :post ->
            apply(mock, :post, [url, body, headers, opts])

          _ ->
            {:error, :method_not_supported}
        end

      _ ->
        # Production mode - use the new middleware-based client
        client_opts = build_client_opts(opts, headers, body)
        result = Client.request(method, url, client_opts)
        transform_response(result)
    end
  end

  # Private implementation

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

  defp transform_response({:ok, response}) do
    # Response is already in the correct format from the new client
    {:ok, response}
  end

  defp transform_response({:error, {:http_error, status, body}}) do
    # Keep the same error format
    {:error, {:http_error, status, body}}
  end

  defp transform_response({:error, reason}) do
    # Other errors pass through
    {:error, reason}
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
