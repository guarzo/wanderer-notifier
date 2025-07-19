defmodule WandererNotifier.Infrastructure.Http.Utils.RateLimiter do
  @moduledoc """
  Unified rate limiting utility for WandererNotifier.

  Provides consistent rate limiting and backoff strategies across the application.
  Handles various rate limiting scenarios including:
  - HTTP 429 responses with retry-after headers
  - Exponential backoff with jitter
  - Fixed interval rate limiting
  - Burst rate limiting
  """

  alias WandererNotifier.Shared.Types.Constants
  alias WandererNotifier.Shared.Logger.ErrorLogger
  alias WandererNotifier.Shared.Logger.Logger, as: AppLogger
  alias WandererNotifier.Shared.Config.Utils, as: ConfigUtils

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
                When true, the function executes immediately but any delays
                (rate limiting or retries) happen asynchronously. Returns
                `{:async, task_ref}` for retry cases instead of blocking.

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
  @spec handle_http_rate_limit(HTTPoison.Response.t(), rate_limit_opts()) ::
          rate_limit_result(term())
  def handle_http_rate_limit(%{status_code: 429, headers: headers}, opts \\ []) do
    retry_after = get_retry_after(headers)
    context = Keyword.get(opts, :context, "HTTP request")

    ErrorLogger.log_api_error("Rate limit hit",
      context: context,
      retry_after: retry_after
    )

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
        # Non-blocking: schedule delay asynchronously using timer
        Process.send_after(self(), :rate_limit_delay_complete, interval_ms)
      else
        # Blocking: maintain existing behavior for backward compatibility
        Process.sleep(interval_ms)
      end

      {:ok, result}
    rescue
      e ->
        ErrorLogger.log_exception("Fixed interval operation failed", e, context: context)
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
        # Non-blocking: schedule delay asynchronously using timer
        Process.send_after(self(), :rate_limit_delay_complete, delay)
      else
        # Blocking: maintain existing behavior for backward compatibility
        :timer.sleep(delay)
      end

      {:ok, result}
    rescue
      e ->
        ErrorLogger.log_exception("Burst operation failed", e, context: context)
        {:error, e}
    end
  end

  # Private implementation

  defp execute_with_rate_limit(fun, state) do
    case fun.() do
      {:ok, result} ->
        {:ok, result}

      {:error, {:rate_limited, retry_after}} when is_integer(retry_after) ->
        handle_rate_limit(fun, state, retry_after)

      {:error, reason} when state.attempt < state.max_retries ->
        handle_retry(fun, state, reason)

      {:error, reason} ->
        {:error, reason}

      other ->
        {:ok, other}
    end
  rescue
    error ->
      if state.attempt < state.max_retries do
        handle_retry(fun, state, error)
      else
        {:error, error}
      end
  end

  defp handle_rate_limit(fun, state, retry_after) do
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

  defp handle_retry(fun, state, error) do
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

  defp get_retry_after(headers) do
    case Enum.find(headers, fn {key, _} -> String.downcase(key) == "retry-after" end) do
      {_, value} -> ConfigUtils.parse_int(value, 0) * 1000
      nil -> Constants.base_backoff()
    end
  end

  defp default_retry_callback(attempt, error, delay) do
    AppLogger.api_info("Rate limit retry",
      attempt: attempt,
      error: inspect(error),
      delay_ms: delay
    )
  end
end
