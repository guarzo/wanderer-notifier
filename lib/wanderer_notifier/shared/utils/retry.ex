defmodule WandererNotifier.Shared.Utils.Retry do
  require Logger

  @moduledoc """
  Retry utility for WandererNotifier.

  Provides consistent retry logic with exponential backoff.
  """

  alias WandererNotifier.Shared.Types.Constants
  alias WandererNotifier.Shared.Utils.TimeUtils

  @type retry_options :: [
          max_attempts: pos_integer(),
          base_backoff: pos_integer(),
          max_backoff: pos_integer(),
          jitter: boolean() | float(),
          on_retry: (pos_integer(), term(), pos_integer() -> :ok),
          retryable_errors: [atom()],
          retryable_status_codes: [pos_integer()],
          context: String.t(),
          mode: :exponential | :fixed | :linear,
          async: boolean(),
          supervisor: atom() | pid(),
          extract_retry_after: (term() -> pos_integer() | nil)
        ]

  @type retry_result(success) :: {:ok, success} | {:error, term()}

  @doc """
  Executes a function with retry logic and exponential backoff.

  ## Options
    * `:max_attempts` - Maximum number of attempts (default: 3)
    * `:base_backoff` - Base backoff delay in milliseconds (default: from Constants)
    * `:max_backoff` - Maximum backoff delay in milliseconds (default: from Constants)
    * `:jitter` - Whether to add random jitter. Boolean or float (0.0-1.0) for jitter percentage (default: true = 0.2)
    * `:on_retry` - Callback function called on each retry attempt
    * `:retryable_errors` - List of atoms representing retryable error types
    * `:retryable_status_codes` - List of HTTP status codes to retry (default: none)
    * `:context` - Context string for logging (default: "operation")
    * `:mode` - Retry mode: :exponential, :fixed, or :linear (default: :exponential)
    * `:async` - Whether to perform retries asynchronously (default: false)
    * `:supervisor` - Task supervisor to use for async retries (default: WandererNotifier.TaskSupervisor)
    * `:extract_retry_after` - Function to extract retry-after value from error (default: nil)
  """
  @spec run(function(), retry_options()) :: retry_result(term())
  def run(fun, opts \\ []) when is_function(fun, 0) and is_list(opts) do
    state = build_retry_state(opts)
    execute_retry(fun, state)
  end

  defp build_retry_state(opts) do
    %{
      max_attempts: Keyword.get(opts, :max_attempts, 3),
      base_backoff: Keyword.get(opts, :base_backoff, Constants.base_backoff()),
      max_backoff: Keyword.get(opts, :max_backoff, Constants.max_backoff()),
      jitter: normalize_jitter(Keyword.get(opts, :jitter, true)),
      on_retry: Keyword.get(opts, :on_retry, &default_retry_callback/3),
      retryable_errors: Keyword.get(opts, :retryable_errors, default_retryable_errors()),
      retryable_status_codes: Keyword.get(opts, :retryable_status_codes, []),
      context: Keyword.get(opts, :context, "operation"),
      mode: Keyword.get(opts, :mode, :exponential),
      async: Keyword.get(opts, :async, false),
      supervisor: Keyword.get(opts, :supervisor, WandererNotifier.TaskSupervisor),
      extract_retry_after: Keyword.get(opts, :extract_retry_after),
      attempt: 1
    }
  end

  defp execute_retry(fun, %{async: true} = state), do: execute_async_retry(fun, state)
  defp execute_retry(fun, state), do: execute_with_retry(fun, state)

  @doc """
  Simplified retry function for HTTP operations with sensible defaults.
  """
  @spec http_retry(function(), keyword()) :: retry_result(term())
  def http_retry(fun, opts \\ []) when is_function(fun, 0) do
    defaults = [
      max_attempts: 3,
      retryable_errors: [:timeout, :connect_timeout, :econnrefused, :ehostunreach],
      retryable_status_codes: [408, 429, 500, 502, 503, 504],
      context: "HTTP request",
      extract_retry_after: &extract_http_retry_after/1
    ]

    run(fun, Keyword.merge(defaults, opts))
  end

  @doc """
  Fixed interval retry - useful for polling operations.
  """
  @spec fixed_retry(function(), pos_integer(), keyword()) :: retry_result(term())
  def fixed_retry(fun, interval, opts \\ []) when is_function(fun, 0) do
    defaults = [
      mode: :fixed,
      base_backoff: interval,
      jitter: false
    ]

    run(fun, Keyword.merge(defaults, opts))
  end

  @doc """
  Calculates backoff delay based on mode with optional jitter.
  """
  @spec calculate_backoff(map()) :: pos_integer()
  def calculate_backoff(state) do
    base_delay = calculate_base_delay(state)

    # Apply jitter if requested
    with_jitter = apply_jitter(base_delay, state.jitter)

    # Cap at maximum backoff
    min(with_jitter, state.max_backoff)
  end

  defp calculate_base_delay(%{mode: :exponential} = state) do
    # Calculate exponential backoff using bit shifting: base * 2^(attempt - 1)
    state.base_backoff * :erlang.bsl(1, state.attempt - 1)
  end

  defp calculate_base_delay(%{mode: :fixed} = state) do
    # Fixed interval - always return base_backoff
    state.base_backoff
  end

  defp calculate_base_delay(%{mode: :linear} = state) do
    # Linear backoff: base * attempt
    state.base_backoff * state.attempt
  end

  defp apply_jitter(delay, jitter) when is_float(jitter) and jitter > 0 do
    # Apply custom jitter percentage
    max_jitter = round(delay * jitter)
    jitter_amount = :rand.uniform(max_jitter + 1) - 1
    delay + jitter_amount
  end

  defp apply_jitter(delay, true) do
    # Default jitter of 20%
    apply_jitter(delay, 0.2)
  end

  defp apply_jitter(delay, _), do: delay

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
    cond do
      state.attempt >= state.max_attempts ->
        {:error, reason}

      retryable_error?(reason, state) ->
        perform_retry(fun, state, reason)

      true ->
        {:error, reason}
    end
  end

  defp handle_exception(error, %{attempt: attempt, max_attempts: max} = state, fun)
       when attempt < max do
    handle_retryable_exception(error, state, fun)
  end

  defp handle_exception(error, _state, _fun), do: {:error, error}

  defp handle_retryable_exception(error, state, fun) do
    case retryable_exception?(error, state.retryable_errors) do
      true -> perform_retry(fun, state, error)
      false -> {:error, error}
    end
  end

  defp perform_retry(fun, state, error) do
    # Check if we can extract a retry-after value
    delay =
      case extract_retry_delay(error, state) do
        nil -> calculate_backoff(state)
        retry_after -> min(retry_after, state.max_backoff)
      end

    # Call the retry callback
    state.on_retry.(state.attempt, error, delay)

    # Wait for the calculated delay
    Process.sleep(delay)

    # Retry with incremented attempt counter
    new_state = %{state | attempt: state.attempt + 1}
    execute_with_retry(fun, new_state)
  end

  defp retryable_error?(reason, state) when is_atom(reason) do
    reason in state.retryable_errors
  end

  defp retryable_error?({reason, _details}, state) when is_atom(reason) do
    reason in state.retryable_errors
  end

  defp retryable_error?({:http_error, status, _body}, state) when is_integer(status) do
    status in state.retryable_status_codes
  end

  defp retryable_error?(%{status_code: status}, state) when is_integer(status) do
    status in state.retryable_status_codes
  end

  defp retryable_error?(_reason, _state), do: false

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
    Logger.info("Retrying operation",
      attempt: attempt,
      error: inspect(error),
      delay_ms: delay
    )
  end

  # Normalizes jitter values for retry backoff calculations.
  # `true` corresponds to the default jitter value (0.2)
  defp normalize_jitter(true), do: 0.2
  defp normalize_jitter(false), do: 0.0

  defp normalize_jitter(jitter) when is_float(jitter) and jitter >= 0.0 and jitter <= 1.0,
    do: jitter

  defp normalize_jitter(_), do: 0.2

  defp execute_async_retry(fun, state) do
    Task.Supervisor.async(state.supervisor, fn -> execute_with_retry(fun, state) end)
  end

  defp extract_retry_delay(error, %{extract_retry_after: extractor}) when is_function(extractor),
    do: extractor.(error)

  defp extract_retry_delay(_error, _state), do: nil

  defp extract_http_retry_after({:error, {:http_error, _status, headers}})
       when is_list(headers) do
    # Look for Retry-After header
    case List.keyfind(headers, "retry-after", 0) do
      {"retry-after", value} -> parse_retry_after(value)
      _ -> nil
    end
  end

  defp extract_http_retry_after(_), do: nil

  defp parse_retry_after(value) when is_binary(value) do
    # Try to parse as integer first (seconds)
    case Integer.parse(value, 10) do
      {seconds, ""} -> seconds * 1000
      _ -> parse_retry_after_as_date(value)
    end
  end

  defp parse_retry_after(value) when is_integer(value), do: value * 1000

  defp parse_retry_after(_), do: nil

  defp parse_retry_after_as_date(value) do
    case TimeUtils.parse_http_date(value) do
      {:ok, datetime} -> calculate_delay_from_datetime(datetime)
      {:error, _} -> nil
    end
  end

  defp calculate_delay_from_datetime(datetime) do
    # Calculate delay from current time in milliseconds
    now = TimeUtils.now()
    delay_seconds = DateTime.diff(datetime, now)

    if delay_seconds > 0 do
      delay_seconds * 1000
    else
      # If the date is in the past, don't retry
      nil
    end
  end
end
