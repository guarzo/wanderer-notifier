defmodule WandererNotifier.Http.Utils.Retry do
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
    # Calculate exponential backoff using bit shifting: base * 2^(attempt - 1)
    # Use bit shifting for integer math to avoid floating point issues
    exponential = base_backoff * :erlang.bsl(1, attempt - 1)

    # Apply jitter if requested (up to 20% of the delay)
    with_jitter =
      if jitter do
        # Calculate jitter as integer (0-20% of exponential)
        # 20% = 1/5
        max_jitter = div(exponential, 5)
        jitter_amount = :rand.uniform(max_jitter + 1) - 1
        exponential + jitter_amount
      else
        exponential
      end

    # Cap at maximum backoff
    min(with_jitter, max_backoff)
  end

  # Private implementation

  defp execute_with_retry(fun, state) do
    try do
      handle_function_result(fun.(), state, fun)
    rescue
      error ->
        handle_exception(error, state, fun)
    end
  end

  defp handle_function_result(result, state, fun) do
    case result do
      {:ok, value} ->
        {:ok, value}

      {:error, reason} ->
        handle_error_result(reason, state, fun)

      other ->
        # Handle non-tuple returns - treat as success
        {:ok, other}
    end
  end

  defp handle_error_result(reason, state, fun) do
    if state.attempt < state.max_attempts and retryable_error?(reason, state.retryable_errors) do
      perform_retry(fun, state, reason)
    else
      {:error, reason}
    end
  end

  defp handle_exception(error, state, fun) do
    if state.attempt < state.max_attempts and retryable_exception?(error, state.retryable_errors) do
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
    # Check if this is a known retryable exception type
    case exception do
      %Mint.TransportError{reason: reason} ->
        # Check if the transport error reason is retryable
        reason in retryable_errors

      %Mint.HTTPError{reason: reason} ->
        # Check if the HTTP error reason is retryable
        reason in retryable_errors

      _ ->
        # For other exceptions, check the module name
        error_type = exception.__struct__
        error_type in retryable_errors
    end
  end

  defp default_retryable_errors do
    # List of retryable error reasons (atoms) and exception modules
    [
      # Network/connection errors
      :timeout,
      :connect_timeout,
      :econnrefused,
      :ehostunreach,
      :enetunreach,
      :econnreset,
      # Also include exception modules if needed
      Mint.TransportError,
      Mint.HTTPError
    ]
  end

  defp default_retry_callback(attempt, error, delay) do
    AppLogger.api_info("Retrying operation",
      attempt: attempt,
      error: inspect(error),
      delay_ms: delay
    )
  end
end
