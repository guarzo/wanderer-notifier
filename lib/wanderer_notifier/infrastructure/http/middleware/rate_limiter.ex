defmodule WandererNotifier.Infrastructure.Http.Middleware.RateLimiter do
  require Logger

  @moduledoc """
  HTTP middleware that implements rate limiting using the Hammer library.

  This middleware provides configurable rate limiting to prevent API abuse and
  respect external service rate limits. It uses Hammer's efficient rate limiting
  with per-host limiting and automatic backoff handling.

  ## Features
  - Efficient rate limiting via Hammer library
  - Per-host rate limiting configuration
  - Handles HTTP 429 responses with Retry-After headers
  - Configurable rate limits
  - Comprehensive logging of rate limit events

  ## Usage

      # Simple rate limiting with defaults
      Client.request(:get, "https://api.example.com/data",
        middlewares: [RateLimiter])

      # Custom rate limiting configuration
      Client.request(:get, "https://api.example.com/data",
        middlewares: [RateLimiter],
        rate_limit_options: [
          requests_per_second: 10,
          per_host: true
        ])
  """

  @behaviour WandererNotifier.Infrastructure.Http.Middleware.MiddlewareBehaviour

  alias WandererNotifier.Infrastructure.Http.Utils.RateLimiter, as: RateLimiterUtils
  alias WandererNotifier.Infrastructure.Http.Utils.HttpUtils

  @type rate_limit_options :: [
          requests_per_second: pos_integer(),
          per_host: boolean(),
          enable_backoff: boolean(),
          context: String.t()
        ]

  @default_requests_per_second 200
  # 1 second window
  @default_scale_ms 1_000

  @doc """
  Generates a bucket key for rate limiting based on request configuration.

  Returns a bucket key that can be used to group requests for rate limiting.
  When `per_host` is true, requests are grouped by host. When false, all
  requests use a global bucket.

  ## Examples

      iex> request = %{url: "https://api.example.com/path", options: [rate_limit: [per_host: true]]}
      iex> bucket_key(request)
      "http_rate_limit:api.example.com"

      iex> request = %{url: "https://api.example.com/path", options: [rate_limit: [per_host: false]]}
      iex> bucket_key(request)
      :global
  """
  def bucket_key(%{url: url, options: options}) do
    rate_limit_options = Keyword.get(options, :rate_limit, [])
    per_host = Keyword.get(rate_limit_options, :per_host, true)

    if per_host do
      host = HttpUtils.extract_host(url)
      "http_rate_limit:#{host}"
    else
      :global
    end
  end

  @doc """
  Executes the HTTP request with rate limiting applied.

  The middleware will enforce rate limits before making requests and handle
  rate limit responses appropriately. Rate limiting behavior is configurable
  through the `:rate_limit_options` key in the request options.
  """
  @impl true
  def call(request, next) do
    # Handle both :opts and :options keys for backward compatibility
    options = Map.get(request, :opts, Map.get(request, :options, []))
    rate_limit_options = get_rate_limit_options(options)
    host = HttpUtils.extract_host(request.url)

    # Check rate limit before making request
    case check_rate_limit(host, rate_limit_options) do
      :ok ->
        # Proceed with request
        result = next.(request)
        handle_response(result, host, rate_limit_options)

      {:error, :rate_limited} ->
        # Rate limit exceeded before request
        {:error, :rate_limited}
    end
  end

  # Private functions

  defp get_rate_limit_options(opts) do
    Keyword.get(opts, :rate_limit, [])
  end

  defp check_rate_limit(host, options) do
    # Use burst_capacity if provided, otherwise fall back to requests_per_second
    limit =
      Keyword.get(
        options,
        :burst_capacity,
        Keyword.get(options, :requests_per_second, @default_requests_per_second)
      )

    per_host = Keyword.get(options, :per_host, true)

    bucket_id = if per_host, do: "http_rate_limit:#{host}", else: :global

    # Use Hammer to check rate limit
    case WandererNotifier.RateLimiter.check_rate(
           bucket_id,
           @default_scale_ms,
           limit
         ) do
      {:allow, _count} ->
        :ok

      {:deny, _limit} ->
        # Rate limit exceeded
        Logger.error("Rate limit denied",
          host: host,
          bucket_id: bucket_id,
          limit: limit,
          category: :api
        )

        log_rate_limit_hit(host, bucket_id)
        {:error, :rate_limited}
    end
  end

  defp handle_response({:ok, response} = result, host, options) do
    case response.status_code do
      429 ->
        # Rate limited by server - handle retry-after
        retry_after = extract_retry_after(response.headers)
        log_server_rate_limit(host, retry_after)

        if Keyword.get(options, :enable_backoff, true) do
          # Use the existing rate limiter utility for handling server rate limits
          RateLimiterUtils.handle_http_rate_limit(response,
            context: build_context(host)
          )
        else
          result
        end

      _ ->
        result
    end
  end

  defp handle_response({:error, _reason} = result, _host, _options) do
    result
  end

  defp extract_retry_after(headers) do
    case Enum.find(headers, fn {key, _} ->
           String.downcase(key) == "retry-after"
         end) do
      {_, value} ->
        case Integer.parse(value) do
          # Convert to milliseconds
          {seconds, _} -> seconds * 1000
          :error -> 0
        end

      nil ->
        0
    end
  end

  defp log_rate_limit_hit(host, bucket_id) do
    Logger.warning("Rate limit exceeded",
      host: host,
      bucket_key: bucket_id,
      middleware: "RateLimiter",
      category: :api
    )
  end

  defp log_server_rate_limit(host, retry_after) do
    Logger.warning("Server rate limit hit",
      host: host,
      retry_after_ms: retry_after,
      middleware: "RateLimiter",
      category: :api
    )
  end

  defp build_context(host) do
    "HTTP rate limit for #{host}"
  end
end
