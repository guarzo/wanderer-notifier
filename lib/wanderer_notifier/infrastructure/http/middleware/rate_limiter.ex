defmodule WandererNotifier.Infrastructure.Http.Middleware.RateLimiter do
  @behaviour WandererNotifier.Infrastructure.Http.Middleware.MiddlewareBehaviour
  require Logger

  @moduledoc """
  Rate limiting for HTTP middleware and general-purpose operations.

  Provides HTTP middleware functionality for request pipeline integration
  and general-purpose rate limiting utilities with exponential backoff.

  ## HTTP Middleware Features
  - Efficient rate limiting via Hammer library
  - Per-host rate limiting configuration
  - Handles HTTP 429 responses with Retry-After headers
  - Configurable rate limits
  - Comprehensive logging of rate limit events

  ## General Rate Limiting Features
  - Exponential backoff with jitter
  - Fixed interval rate limiting
  - Burst rate limiting
  - Async execution support
  - HTTP 429 response handling

  ## Usage Examples

      # HTTP middleware
      Client.request(:get, "https://api.example.com/data",
        middlewares: [RateLimiter])

      # Custom bucket key (overrides per-host/global keying)
      Client.request(:post, url, body, headers,
        rate_limit: [bucket_key: "my-bucket"])

      # General rate limiting
      RateLimiter.run(fn -> HTTPClient.get("https://api.example.com") end)

      # Fixed interval operations
      RateLimiter.fixed_interval(fn -> poll_api() end, 5000)
  """

  alias WandererNotifier.Infrastructure.Http.Utils.HttpUtils
  alias WandererNotifier.Shared.Types.Constants

  @type rate_limit_options :: [
          requests_per_second: pos_integer(),
          per_host: boolean(),
          bucket_key: String.t(),
          burst_capacity: pos_integer(),
          enable_backoff: boolean(),
          context: String.t()
        ]

  @type rate_limit_opts :: [
          max_retries: pos_integer(),
          base_backoff: pos_integer(),
          max_backoff: pos_integer(),
          jitter: boolean(),
          on_retry: (pos_integer(), term(), pos_integer() -> :ok),
          context: String.t(),
          async: boolean()
        ]

  @type rate_limit_result(success) :: {:ok, success} | {:error, term()} | {:async, Task.t()}

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
    host = HttpUtils.extract_host(url)
    resolve_bucket_id(host, rate_limit_options)
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
      {:ok, :allowed} ->
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

    bucket_id = resolve_bucket_id(host, options)

    # Use our RateLimiter module to hit the rate limit bucket
    case WandererNotifier.Infrastructure.RateLimiter.hit(
           bucket_id,
           @default_scale_ms,
           limit
         ) do
      {:allow, _count} ->
        {:ok, :allowed}

      {:deny, _limit} ->
        # Rate limit exceeded
        Logger.error(
          "Rate limit denied - host: #{host}, bucket_id: #{bucket_id}, limit: #{limit}"
        )

        log_rate_limit_hit(host, bucket_id)
        {:error, :rate_limited}
    end
  end

  # Resolve the rate limit bucket ID. Supports:
  # - :bucket_key option for custom keying (e.g., per-bot-token)
  # - :per_host for per-host keying (default)
  # - :global fallback
  defp resolve_bucket_id(host, options) when is_list(options) do
    case Keyword.get(options, :bucket_key) do
      key when is_binary(key) ->
        key

      nil ->
        resolve_bucket_id_for_host(host, Keyword.get(options, :per_host, true))

      other ->
        Logger.warning("Non-binary :bucket_key option ignored",
          bucket_key: inspect(other),
          host: host
        )

        resolve_bucket_id_for_host(host, Keyword.get(options, :per_host, true))
    end
  end

  defp resolve_bucket_id_for_host(host, true), do: "http_rate_limit:#{host}"
  defp resolve_bucket_id_for_host(_host, false), do: :global

  defp handle_response({:ok, response} = result, host, options) do
    case response.status_code do
      429 ->
        # Rate limited by server - handle retry-after
        retry_after = extract_retry_after(response.headers)
        log_server_rate_limit(host, retry_after)

        if Keyword.get(options, :enable_backoff, true) do
          # Handle server rate limits directly
          handle_http_rate_limit(response, context: build_context(host))
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
    case find_retry_after_header(headers) do
      {_, value} when is_binary(value) ->
        parse_binary_retry_after(value)

      {_, value} ->
        parse_non_binary_retry_after(value)

      nil ->
        0
    end
  end

  defp find_retry_after_header(headers) do
    Enum.find(headers, fn {key, _} ->
      String.downcase(key) == "retry-after"
    end)
  end

  defp parse_binary_retry_after(value) do
    case Integer.parse(value, 10) do
      {seconds, _} -> seconds * 1000
      :error -> 0
    end
  end

  defp parse_non_binary_retry_after(value) do
    log_non_binary_header(value)

    cond do
      is_integer(value) ->
        value * 1000

      is_list(value) and value != [] ->
        parse_list_retry_after(value)

      is_atom(value) and not is_nil(value) ->
        5000

      true ->
        5000
    end
  end

  defp parse_list_retry_after(value) do
    case List.first(value) do
      val when is_binary(val) ->
        parse_list_binary_value(val)

      val when is_integer(val) ->
        val * 1000

      _ ->
        5000
    end
  end

  defp parse_list_binary_value(val) do
    case Integer.parse(val, 10) do
      {int, ""} -> int * 1000
      _ -> 5000
    end
  end

  defp log_non_binary_header(value) do
    value_type = determine_value_type(value)

    Logger.warning("Non-binary retry-after header value: #{inspect(value)} (type: #{value_type})")
  end

  defp determine_value_type(value) do
    cond do
      is_list(value) -> :list
      is_integer(value) -> :integer
      is_atom(value) -> :atom
      is_map(value) -> :map
      true -> :unknown
    end
  end

  defp log_rate_limit_hit(host, bucket_id) do
    Logger.warning(
      "Rate limit exceeded - host: #{host}, bucket_key: #{bucket_id}, middleware: RateLimiter"
    )
  end

  defp log_server_rate_limit(host, retry_after) do
    Logger.warning("Server rate limit hit - host: #{host}, retry_after_ms: #{retry_after}")
  end

  defp build_context(host) do
    "HTTP rate limit for #{host}"
  end

  # ═══════════════════════════════════════════════════════════════════════════════
  # General-Purpose Rate Limiting Functions (consolidated from utils/rate_limiter.ex)
  # ═══════════════════════════════════════════════════════════════════════════════

  @doc """
  Executes a function with rate limiting and exponential backoff.

  ## Options
    * `:max_retries` - Maximum number of retries (default: 3)
    * `:base_backoff` - Base backoff delay in milliseconds (default: from Constants)
    * `:max_backoff` - Maximum backoff delay in milliseconds (default: from Constants)
    * `:jitter` - Whether to add random jitter to backoff (default: true)
    * `:on_retry` - Callback function called on each retry attempt
    * `:context` - Context string for logging (default: "operation")
    * `:async` - Whether to handle delays and retries asynchronously (default: false)

  ## Examples
      # Simple rate limiting with defaults
      RateLimiter.run(fn -> HTTPClient.get("https://api.example.com") end)

      # Rate limiting with custom options
      RateLimiter.run(
        fn -> fetch_data() end,
        max_retries: 5,
        base_backoff: 1000,
        context: "fetch external data"
      )
  """
  @spec run(function(), rate_limit_opts()) :: rate_limit_result(term())
  def run(fun, opts \\ []) when is_function(fun, 0) and is_list(opts) do
    max_retries = Keyword.get(opts, :max_retries, Constants.max_retries())
    base_backoff = Keyword.get(opts, :base_backoff, Constants.base_backoff())
    max_backoff = Keyword.get(opts, :max_backoff, Constants.max_backoff())
    jitter = Keyword.get(opts, :jitter, true)
    on_retry = Keyword.get(opts, :on_retry, &default_retry_callback/3)
    context = Keyword.get(opts, :context, "operation")
    async = Keyword.get(opts, :async, false)

    execute_with_rate_limit(fun, %{
      max_retries: max_retries,
      base_backoff: base_backoff,
      max_backoff: max_backoff,
      jitter: jitter,
      on_retry: on_retry,
      context: context,
      async: async,
      attempt: 1
    })
  end

  @doc """
  Handles HTTP rate limit responses (429) with retry-after header.
  """
  @spec handle_http_rate_limit(map(), rate_limit_opts()) ::
          rate_limit_result(term())
  def handle_http_rate_limit(%{status_code: 429, headers: headers}, opts \\ []) do
    retry_after = get_retry_after_from_headers(headers)
    context = Keyword.get(opts, :context, "HTTP request")

    Logger.error("Rate limit hit - context: #{context}, retry_after: #{retry_after}")

    {:error, {:rate_limited, retry_after}}
  end

  @doc """
  Implements a fixed interval rate limiter.
  """
  @spec fixed_interval(function(), pos_integer(), rate_limit_opts()) :: rate_limit_result(term())
  def fixed_interval(fun, interval_ms, opts \\ [])
      when is_function(fun, 0) and is_integer(interval_ms) do
    context = Keyword.get(opts, :context, "fixed interval operation")
    async = Keyword.get(opts, :async, false)

    try do
      result = fun.()

      if async do
        # Non-blocking: return a Task that sleeps for the interval
        Task.async(fn -> Process.sleep(interval_ms) end)
      else
        # Blocking: maintain existing behavior for backward compatibility
        Process.sleep(interval_ms)
      end

      {:ok, result}
    rescue
      e ->
        Logger.error(
          "Fixed interval operation failed: #{Exception.message(e)} - context: #{context}"
        )

        {:error, e}
    end
  end

  @doc """
  Implements a burst rate limiter that allows N operations per time window.
  """
  @spec burst_limit(function(), pos_integer(), pos_integer(), rate_limit_opts()) ::
          rate_limit_result(term())
  def burst_limit(fun, max_operations, window_ms, opts \\ [])
      when is_function(fun, 0) and is_integer(max_operations) and is_integer(window_ms) do
    context = Keyword.get(opts, :context, "burst operation")
    async = Keyword.get(opts, :async, false)

    try do
      result = fun.()
      delay = div(window_ms, max_operations)

      if async do
        # Non-blocking: return a Task that sleeps for the delay
        Task.async(fn -> :timer.sleep(delay) end)
      else
        # Blocking: maintain existing behavior for backward compatibility
        :timer.sleep(delay)
      end

      {:ok, result}
    rescue
      e ->
        Logger.error("Burst operation failed: #{Exception.message(e)} - context: #{context}")

        {:error, e}
    end
  end

  # Private implementation for general rate limiting

  defp execute_with_rate_limit(fun, state) do
    case fun.() do
      {:ok, result} ->
        {:ok, result}

      {:error, {:rate_limited, retry_after}} when is_integer(retry_after) ->
        handle_rate_limit_with_retry(fun, state, retry_after)

      {:error, reason} when state.attempt < state.max_retries ->
        handle_retry_with_backoff(fun, state, reason)

      {:error, reason} ->
        {:error, reason}

      other ->
        {:ok, other}
    end
  rescue
    error ->
      if state.attempt < state.max_retries do
        handle_retry_with_backoff(fun, state, error)
      else
        {:error, error}
      end
  end

  defp handle_rate_limit_with_retry(fun, state, retry_after) do
    # Call the retry callback
    state.on_retry.(state.attempt, :rate_limited, retry_after)

    if Map.get(state, :async, false) do
      # Async: return task struct for the caller to handle
      task =
        Task.Supervisor.async_nolink(WandererNotifier.TaskSupervisor, fn ->
          :timer.sleep(retry_after)
          new_state = %{state | attempt: state.attempt + 1}
          execute_with_rate_limit(fun, new_state)
        end)

      {:async, task}
    else
      # Blocking: maintain existing behavior
      Process.sleep(retry_after)
      new_state = %{state | attempt: state.attempt + 1}
      execute_with_rate_limit(fun, new_state)
    end
  end

  defp handle_retry_with_backoff(fun, state, error) do
    delay = calculate_backoff(state.attempt, state.base_backoff, state.max_backoff, state.jitter)

    # Call the retry callback
    state.on_retry.(state.attempt, error, delay)

    if Map.get(state, :async, false) do
      # Async: return task struct for the caller to handle
      task =
        Task.Supervisor.async_nolink(WandererNotifier.TaskSupervisor, fn ->
          :timer.sleep(delay)
          new_state = %{state | attempt: state.attempt + 1}
          execute_with_rate_limit(fun, new_state)
        end)

      {:async, task}
    else
      # Blocking: maintain existing behavior
      Process.sleep(delay)
      new_state = %{state | attempt: state.attempt + 1}
      execute_with_rate_limit(fun, new_state)
    end
  end

  defp calculate_backoff(attempt, base_backoff, max_backoff, jitter) do
    # Calculate exponential backoff: base * 2^(attempt - 1)
    exponential = base_backoff * :math.pow(2, attempt - 1)

    # Apply jitter if requested (up to 20% of the delay)
    with_jitter =
      if jitter do
        jitter_amount = exponential * 0.2 * :rand.uniform()
        exponential + jitter_amount
      else
        exponential
      end

    # Cap at maximum backoff
    min(with_jitter, max_backoff)
    |> round()
  end

  defp get_retry_after_from_headers(headers) do
    case Enum.find(headers, fn {key, _} -> String.downcase(key) == "retry-after" end) do
      # Default to 5 seconds if parse fails
      {_, value} -> parse_int(value, 5) * 1000
      nil -> Constants.base_backoff()
    end
  end

  defp default_retry_callback(attempt, error, delay) do
    Logger.info(
      "Rate limit retry - attempt: #{attempt}, error: #{inspect(error)}, delay_ms: #{delay}"
    )
  end

  # Simple parse_int helper to replace Config.Utils
  defp parse_int(nil, default), do: default
  defp parse_int(value, _default) when is_integer(value), do: value

  defp parse_int(value, default) when is_binary(value) do
    case Integer.parse(value, 10) do
      {int, ""} -> int
      _ -> default
    end
  end

  defp parse_int(value, default) when is_list(value) and value != [] do
    # Handle list case - parse first element
    case List.first(value) do
      val when is_binary(val) -> parse_int(val, default)
      val when is_integer(val) -> val
      _ -> default
    end
  end

  defp parse_int(_, default), do: default
end
