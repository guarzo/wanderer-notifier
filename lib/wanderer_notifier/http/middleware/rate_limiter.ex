defmodule WandererNotifier.Http.Middleware.RateLimiter do
  @moduledoc """
  HTTP middleware that implements token bucket rate limiting for HTTP requests.

  This middleware provides configurable rate limiting to prevent API abuse and
  respect external service rate limits. It uses a token bucket algorithm with
  per-host rate limiting and automatic backoff handling.

  ## Features
  - Token bucket rate limiting algorithm
  - Per-host rate limiting configuration
  - Handles HTTP 429 responses with Retry-After headers
  - Configurable rate limits and burst capacity
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
          burst_capacity: 20,
          per_host: true
        ])
  """

  @behaviour WandererNotifier.Http.Middleware.MiddlewareBehaviour

  alias WandererNotifier.Http.Utils.RateLimiter, as: RateLimiterUtils
  alias WandererNotifier.Http.Utils.HttpUtils
  alias WandererNotifier.Logger.Logger, as: AppLogger

  @type rate_limit_options :: [
          requests_per_second: pos_integer(),
          burst_capacity: pos_integer(),
          per_host: boolean(),
          enable_backoff: boolean(),
          context: String.t()
        ]

  @default_requests_per_second 10
  @default_burst_capacity 20
  @table_name :http_rate_limiter_buckets

  @doc """
  Returns the ETS table name used for rate limiting buckets.
  """
  def table_name, do: @table_name

  # Ensure ETS table exists for token bucket storage
  def ensure_table do
    case :ets.whereis(@table_name) do
      :undefined ->
        :ets.new(@table_name, [
          :named_table,
          :public,
          :set,
          read_concurrency: true,
          write_concurrency: true
        ])

      _table ->
        :ok
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
    burst_capacity = Keyword.get(options, :burst_capacity, @default_burst_capacity)
    per_host = Keyword.get(options, :per_host, true)

    bucket_key = if per_host, do: "http_rate_limit:#{host}", else: "http_rate_limit:global"

    # Token bucket implementation using ETS for shared storage
    case get_or_create_bucket(bucket_key, burst_capacity) do
      {:ok, tokens} when tokens > 0 ->
        # Consume a token
        update_bucket(bucket_key, tokens - 1, requests_per_second, burst_capacity)
        :ok

      {:ok, 0} ->
        # No tokens available
        log_rate_limit_hit(host, bucket_key)
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

  defp get_or_create_bucket(bucket_key, burst_capacity) do
    ensure_table()

    case :ets.lookup(@table_name, bucket_key) do
      [] ->
        # Create new bucket with full capacity
        bucket = %{
          tokens: burst_capacity,
          last_refill: :erlang.system_time(:second)
        }

        :ets.insert(@table_name, {bucket_key, bucket})
        {:ok, burst_capacity}

      [{^bucket_key, bucket}] ->
        {:ok, bucket.tokens}
    end
  end

  defp update_bucket(bucket_key, new_tokens, refill_rate, burst_capacity) do
    ensure_table()
    current_time = :erlang.system_time(:second)

    case :ets.lookup(@table_name, bucket_key) do
      [] ->
        :ok

      [{^bucket_key, bucket}] ->
        # Calculate token refill based on time elapsed
        time_diff = current_time - bucket.last_refill
        tokens_to_add = time_diff * refill_rate

        # Update bucket with proper token calculation
        updated_tokens = min(new_tokens + tokens_to_add, burst_capacity)

        updated_bucket = %{
          tokens: updated_tokens,
          last_refill: current_time
        }

        :ets.insert(@table_name, {bucket_key, updated_bucket})
        :ok
    end
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

  defp log_rate_limit_hit(host, bucket_key) do
    AppLogger.api_warn("Rate limit exceeded", %{
      host: host,
      bucket_key: bucket_key,
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
