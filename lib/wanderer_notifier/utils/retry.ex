defmodule WandererNotifier.Utils.Retry do
  @moduledoc """
  Unified retry utility for WandererNotifier.

  Provides consistent retry logic with exponential backoff across the application.
  Replaces scattered retry implementations in HTTP clients, RedisQ client, and other modules.
  """

  alias WandererNotifier.Constants
  alias WandererNotifier.Logger.Logger, as: AppLogger

  @type retry_options :: [
          max_attempts: pos_integer(),
          base_backoff: pos_integer(),
          max_backoff: pos_integer(),
          jitter: boolean(),
          on_retry: (pos_integer(), term(), pos_integer() -> :ok),
          retryable_errors: [atom()],
          context: String.t()
        ]

  @type retry_result(success) :: {:ok, success} | {:error, term()}

  @doc """
  Executes a function with retry logic and exponential backoff.

  ## Options
    * `:max_attempts` - Maximum number of attempts (default: 3)
    * `:base_backoff` - Base backoff delay in milliseconds (default: from Constants)
    * `:max_backoff` - Maximum backoff delay in milliseconds (default: from Constants)
    * `:jitter` - Whether to add random jitter to backoff (default: true)
    * `:on_retry` - Callback function called on each retry attempt
    * `:retryable_errors` - List of atoms representing retryable error types
    * `:context` - Context string for logging (default: "operation")

  ## Examples
      # Simple retry with defaults
      Retry.run(fn -> HTTPClient.get("https://api.example.com") end)

      # Retry with custom options
      Retry.run(
        fn -> fetch_data() end,
        max_attempts: 5,
        base_backoff: 1000,
        retryable_errors: [:timeout, :connect_timeout],
        context: "fetch external data"
      )

      # With custom retry callback
      Retry.run(
        fn -> api_call() end,
        on_retry: fn attempt, error, delay ->
          Logger.warn("Retry attempt #{attempt} after error: #{inspect(error)}, waiting #{delay}ms")
        end
      )
  """
  @spec run(function(), retry_options()) :: retry_result(term())
  def run(fun, opts \\ []) when is_function(fun, 0) and is_list(opts) do
    max_attempts = Keyword.get(opts, :max_attempts, 3)
    base_backoff = Keyword.get(opts, :base_backoff, Constants.base_backoff())
    max_backoff = Keyword.get(opts, :max_backoff, Constants.max_backoff())
    jitter = Keyword.get(opts, :jitter, true)
    on_retry = Keyword.get(opts, :on_retry, &default_retry_callback/3)
    retryable_errors = Keyword.get(opts, :retryable_errors, default_retryable_errors())
    context = Keyword.get(opts, :context, "operation")

    execute_with_retry(fun, %{
      max_attempts: max_attempts,
      base_backoff: base_backoff,
      max_backoff: max_backoff,
      jitter: jitter,
      on_retry: on_retry,
      retryable_errors: retryable_errors,
      context: context,
      attempt: 1
    })
  end

  @doc """
  Simplified retry function for HTTP operations with sensible defaults.
  """
  @spec http_retry(function()) :: retry_result(term())
  def http_retry(fun) when is_function(fun, 0) do
    run(fun,
      max_attempts: 3,
      retryable_errors: [:timeout, :connect_timeout, :econnrefused, :ehostunreach],
      context: "HTTP request"
    )
  end

  @doc """
  Calculates exponential backoff delay with optional jitter.
  """
  @spec calculate_backoff(pos_integer(), pos_integer(), pos_integer(), boolean()) :: pos_integer()
  def calculate_backoff(attempt, base_backoff, max_backoff, jitter \\ true) do
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

  # Private implementation

  defp execute_with_retry(fun, state) do
    case fun.() do
      {:ok, result} ->
        {:ok, result}

      {:error, reason} when state.attempt < state.max_attempts ->
        if retryable_error?(reason, state.retryable_errors) do
          perform_retry(fun, state, reason)
        else
          {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}

      other ->
        # Handle non-tuple returns - treat as success
        {:ok, other}
    end
  rescue
    error ->
      if state.attempt < state.max_attempts and
           retryable_exception?(error, state.retryable_errors) do
        perform_retry(fun, state, error)
      else
        {:error, error}
      end
  end

  defp perform_retry(fun, state, error) do
    delay = calculate_backoff(state.attempt, state.base_backoff, state.max_backoff, state.jitter)

    # Call the retry callback
    state.on_retry.(state.attempt, error, delay)

    # Wait for the calculated delay
    :timer.sleep(delay)

    # Retry with incremented attempt counter
    new_state = %{state | attempt: state.attempt + 1}
    execute_with_retry(fun, new_state)
  end

  defp retryable_error?(reason, retryable_errors) when is_atom(reason) do
    reason in retryable_errors
  end

  defp retryable_error?({reason, _details}, retryable_errors) when is_atom(reason) do
    reason in retryable_errors
  end

  defp retryable_error?(_reason, _retryable_errors), do: false

  defp retryable_exception?(exception, retryable_errors) do
    error_type =
      case exception do
        %{__exception__: true} -> exception.__struct__
        _ -> :unknown_exception
      end

    error_type in retryable_errors
  end

  defp default_retryable_errors do
    [:timeout, :connect_timeout, :econnrefused, :ehostunreach, :enetunreach, :econnreset]
  end

  defp default_retry_callback(attempt, error, delay) do
    AppLogger.api_info("Retrying operation",
      attempt: attempt,
      error: inspect(error),
      delay_ms: delay
    )
  end
end
