defmodule WandererNotifier.Http.Middleware.RateLimiter do
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

  @behaviour WandererNotifier.Http.Middleware.MiddlewareBehaviour

  alias WandererNotifier.Http.Utils.RateLimiter, as: RateLimiterUtils
  alias WandererNotifier.Http.Utils.HttpUtils
  alias WandererNotifier.Logger.Logger, as: AppLogger

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
  Executes the HTTP request with rate limiting applied.

  The middleware will enforce rate limits before making requests and handle
  rate limit responses appropriately. Rate limiting behavior is configurable
  through the `:rate_limit_options` key in the request options.
  """
  @impl true
  def call(request, next) do
    rate_limit_options = get_rate_limit_options(request.opts)
    host = HttpUtils.extract_host(request.url)

    # Check rate limit before making request
    case check_rate_limit(host, rate_limit_options) do
      :ok ->
        # Proceed with request
        result = next.(request)
        handle_response(result, host, rate_limit_options)

      {:error, :rate_limited} ->
        # Rate limit exceeded before request
        {:error, {:rate_limited, "Rate limit exceeded for #{host}"}}
    end
  end

  # Private functions

  defp get_rate_limit_options(opts) do
    Keyword.get(opts, :rate_limit_options, [])
  end

  defp check_rate_limit(host, options) do
    requests_per_second = Keyword.get(options, :requests_per_second, @default_requests_per_second)
    per_host = Keyword.get(options, :per_host, true)

    bucket_id = if per_host, do: "http_rate_limit:#{host}", else: "http_rate_limit:global"

    # Debug logging to see what's happening
    AppLogger.api_info("Rate limit check", %{
      host: host,
      bucket_id: bucket_id,
      requests_per_second: requests_per_second,
      options: options
    })

    # Use Hammer to check rate limit
    case Hammer.check_rate(bucket_id, @default_scale_ms, requests_per_second) do
      {:allow, count} ->
        AppLogger.api_info("Rate limit allowed", %{
          host: host,
          bucket_id: bucket_id,
          current_count: count,
          limit: requests_per_second
        })

        :ok

      {:deny, limit} ->
        # Rate limit exceeded
        AppLogger.api_error("Rate limit denied", %{
          host: host,
          bucket_id: bucket_id,
          limit: limit,
          requests_per_second: requests_per_second
        })

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
    AppLogger.api_warn("Rate limit exceeded", %{
      host: host,
      bucket_key: bucket_id,
      middleware: "RateLimiter"
    })
  end

  defp log_server_rate_limit(host, retry_after) do
    AppLogger.api_warn("Server rate limit hit", %{
      host: host,
      retry_after_ms: retry_after,
      middleware: "RateLimiter"
    })
  end

  defp build_context(host) do
    "HTTP rate limit for #{host}"
  end
end
