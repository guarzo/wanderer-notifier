defmodule WandererNotifier.Shared.Utils.ErrorHandler do
  @moduledoc """
  Centralized error handling utilities for consistent error management across the application.

  This module provides:
  - Standard error tuple formats
  - Error transformation and normalization
  - Consistent error logging
  - Error context enrichment
  - HTTP error mapping

  ## Error Format Standards

  All errors should follow these patterns:
  - `{:error, :atom}` - Simple errors without context
  - `{:error, {:category, details}}` - Categorized errors with context
  - Never use `{:error, "string"}` - Always use atoms or tagged tuples

  ## Common Error Atoms

  - `:timeout` - Operation timed out
  - `:not_found` - Resource not found
  - `:unauthorized` - Authentication required
  - `:forbidden` - Access denied
  - `:rate_limited` - Rate limit exceeded
  - `:service_unavailable` - External service down
  - `:invalid_data` - Data validation failed
  - `:network_error` - Network connectivity issue
  """

  require Logger

  @type error_reason :: atom() | {atom(), any()}
  @type error_tuple :: {:error, error_reason()}
  @type result :: {:ok, any()} | error_tuple()

  # Standard error categories
  @network_errors [:timeout, :connect_timeout, :closed, :network_error]
  @http_errors 400..599
  @data_errors [:invalid_json, :invalid_data, :missing_fields, :validation_error]
  @service_errors [:service_unavailable, :rate_limited, :circuit_breaker_open]
  @auth_errors [:unauthorized, :forbidden, :invalid_token]

  @doc """
  Normalizes various error formats into standard error tuples.

  ## Examples

      iex> normalize_error({:error, "timeout"})
      {:error, :timeout}

      iex> normalize_error(:timeout)
      {:error, :timeout}

      iex> normalize_error({:error, {:http_error, 404}})
      {:error, {:http_error, 404}}
  """
  @spec normalize_error(any()) :: error_tuple()
  def normalize_error({:error, reason}) when is_binary(reason) do
    # Convert string errors to atoms when possible
    {:error, string_to_error_atom(reason)}
  end

  def normalize_error({:error, reason}), do: {:error, reason}
  def normalize_error(:ok), do: {:error, :unknown_error}
  def normalize_error(error) when is_atom(error), do: {:error, error}
  def normalize_error(error), do: {:error, {:unknown_error, error}}

  @doc """
  Wraps a function call with standardized error handling.

  ## Examples

      iex> with_error_handling(fn -> {:ok, "success"} end)
      {:ok, "success"}

      iex> with_error_handling(fn -> raise "oops" end)
      {:error, {:exception, %RuntimeError{message: "oops"}}}
  """
  @spec with_error_handling((-> result())) :: result()
  def with_error_handling(fun) when is_function(fun, 0) do
    fun.()
  rescue
    exception ->
      log_exception(exception, __STACKTRACE__)
      {:error, {:exception, exception}}
  catch
    :exit, reason ->
      log_error("Process exit", reason, %{})
      {:error, {:exit, reason}}
  end

  @doc """
  Wraps a function call with timeout handling.

  ## Examples

      iex> with_timeout(fn -> :timer.sleep(10); {:ok, "done"} end, 100)
      {:ok, "done"}

      iex> with_timeout(fn -> :timer.sleep(200) end, 100)
      {:error, :timeout}
  """
  @spec with_timeout((-> result()), non_neg_integer()) :: result()
  def with_timeout(fun, timeout_ms) when is_function(fun, 0) and is_integer(timeout_ms) do
    task = Task.async(fun)

    case Task.yield(task, timeout_ms) || Task.shutdown(task) do
      {:ok, result} -> result
      nil -> {:error, :timeout}
    end
  end

  @doc """
  Maps HTTP status codes to standardized error tuples.

  ## Examples

      iex> http_error_to_tuple(404)
      {:error, :not_found}

      iex> http_error_to_tuple(429)
      {:error, :rate_limited}

      iex> http_error_to_tuple(500)
      {:error, {:http_error, 500}}
  """
  @spec http_error_to_tuple(integer()) :: error_tuple()
  def http_error_to_tuple(status) when status in 400..499 do
    case status do
      400 -> {:error, :bad_request}
      401 -> {:error, :unauthorized}
      403 -> {:error, :forbidden}
      404 -> {:error, :not_found}
      408 -> {:error, :timeout}
      429 -> {:error, :rate_limited}
      _ -> {:error, {:http_error, status}}
    end
  end

  def http_error_to_tuple(status) when status in 500..599 do
    case status do
      500 -> {:error, :internal_server_error}
      502 -> {:error, :bad_gateway}
      503 -> {:error, :service_unavailable}
      504 -> {:error, :gateway_timeout}
      _ -> {:error, {:http_error, status}}
    end
  end

  def http_error_to_tuple(status), do: {:error, {:http_error, status}}

  @doc """
  Categorizes an error reason into standard categories.

  ## Examples

      iex> categorize_error(:timeout)
      :network

      iex> categorize_error(:unauthorized)
      :auth

      iex> categorize_error({:validation_error, "invalid"})
      :data
  """
  @spec categorize_error(error_reason()) :: atom()
  def categorize_error(reason) when reason in @network_errors, do: :network
  def categorize_error(reason) when reason in @auth_errors, do: :auth
  def categorize_error(reason) when reason in @data_errors, do: :data
  def categorize_error(reason) when reason in @service_errors, do: :service

  def categorize_error({:http_error, status}) when status in @http_errors do
    cond do
      status in 400..499 -> :client_error
      status in 500..599 -> :server_error
      true -> :http
    end
  end

  def categorize_error({category, _details}) when is_atom(category), do: category
  def categorize_error(_), do: :unknown

  @doc """
  Logs an error with consistent formatting and metadata.

  ## Examples

      iex> log_error("Operation failed", :timeout, %{user_id: 123})
      :ok
  """
  @spec log_error(String.t(), error_reason(), map()) :: :ok
  def log_error(message, reason, metadata \\ %{}) do
    category = categorize_error(reason)

    full_metadata =
      Map.merge(metadata, %{
        error_reason: inspect(reason),
        error_category: category,
        timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
      })

    Logger.error(message, full_metadata)
  end

  @doc """
  Formats an error for user-friendly display.

  ## Examples

      iex> format_error(:not_found)
      "Resource not found"

      iex> format_error({:validation_error, "name required"})
      "Validation error: name required"
  """
  @spec format_error(error_reason()) :: String.t()
  def format_error(:timeout), do: "Operation timed out"
  def format_error(:not_found), do: "Resource not found"
  def format_error(:unauthorized), do: "Authentication required"
  def format_error(:forbidden), do: "Access denied"
  def format_error(:rate_limited), do: "Rate limit exceeded"
  def format_error(:service_unavailable), do: "Service temporarily unavailable"
  def format_error(:network_error), do: "Network connection error"
  def format_error(:invalid_data), do: "Invalid data provided"

  def format_error({:http_error, status}), do: "HTTP error: #{status}"
  def format_error({:validation_error, details}), do: "Validation error: #{details}"

  def format_error({:exception, exception}),
    do: "Unexpected error: #{Exception.message(exception)}"

  def format_error({category, details}) when is_atom(category) do
    "#{humanize_atom(category)}: #{inspect(details)}"
  end

  def format_error(reason), do: "Error: #{inspect(reason)}"

  @doc """
  Enriches an error with additional context.

  ## Examples

      iex> enrich_error({:error, :not_found}, %{resource: "user", id: 123})
      {:error, {:not_found, %{resource: "user", id: 123}}}
  """
  @spec enrich_error(error_tuple(), map()) :: error_tuple()
  def enrich_error({:error, reason}, context) when is_map(context) do
    case reason do
      atom when is_atom(atom) ->
        {:error, {atom, context}}

      {category, existing_context} when is_map(existing_context) ->
        {:error, {category, Map.merge(existing_context, context)}}

      {category, details} ->
        {:error, {category, Map.put(context, :details, details)}}

      _ ->
        {:error, {:enriched_error, Map.put(context, :original, reason)}}
    end
  end

  def enrich_error(error, _context), do: error

  @doc """
  Retries an operation with exponential backoff on specific errors.

  ## Examples

      iex> with_retry(fn -> {:ok, "success"} end, max_attempts: 3)
      {:ok, "success"}

      iex> with_retry(fn -> {:error, :timeout} end, max_attempts: 2, retry_on: [:timeout])
      {:error, :timeout}  # After 2 attempts
  """
  @spec with_retry((-> result()), keyword()) :: result()
  def with_retry(fun, opts \\ []) do
    max_attempts = Keyword.get(opts, :max_attempts, 3)
    retry_on = Keyword.get(opts, :retry_on, @network_errors)
    base_delay = Keyword.get(opts, :base_delay, 100)

    do_retry(fun, max_attempts, retry_on, base_delay, 1)
  end

  defp do_retry(fun, max_attempts, retry_on, base_delay, attempt) do
    case fun.() do
      {:error, reason} = error when attempt < max_attempts ->
        if should_retry?(reason, retry_on) do
          delay = (base_delay * :math.pow(2, attempt - 1)) |> round()
          log_retry(reason, attempt, max_attempts, delay)
          Process.sleep(delay)
          do_retry(fun, max_attempts, retry_on, base_delay, attempt + 1)
        else
          error
        end

      result ->
        result
    end
  end

  defp should_retry?(reason, retry_on) when is_list(retry_on) do
    case reason do
      atom when is_atom(atom) -> atom in retry_on
      {category, _} when is_atom(category) -> category in retry_on
      _ -> false
    end
  end

  @doc """
  Aggregates multiple results, returning all successes or first error.

  ## Examples

      iex> aggregate_results([{:ok, 1}, {:ok, 2}, {:ok, 3}])
      {:ok, [1, 2, 3]}

      iex> aggregate_results([{:ok, 1}, {:error, :failed}, {:ok, 3}])
      {:error, :failed}
  """
  @spec aggregate_results([result()]) :: {:ok, [any()]} | error_tuple()
  def aggregate_results(results) when is_list(results) do
    results
    |> Enum.reduce_while({:ok, []}, fn
      {:ok, value}, {:ok, acc} -> {:cont, {:ok, [value | acc]}}
      {:error, _} = error, _ -> {:halt, error}
    end)
    |> case do
      {:ok, values} -> {:ok, Enum.reverse(values)}
      error -> error
    end
  end

  @doc """
  Converts an error tuple to an HTTP status code.

  ## Examples

      iex> error_to_status({:error, :not_found})
      404

      iex> error_to_status({:error, :unauthorized})
      401
  """
  @spec error_to_status(error_tuple()) :: integer()
  def error_to_status({:error, :bad_request}), do: 400
  def error_to_status({:error, :unauthorized}), do: 401
  def error_to_status({:error, :forbidden}), do: 403
  def error_to_status({:error, :not_found}), do: 404
  def error_to_status({:error, :timeout}), do: 408
  def error_to_status({:error, :rate_limited}), do: 429
  def error_to_status({:error, {:http_error, status}}), do: status
  def error_to_status({:error, :service_unavailable}), do: 503
  def error_to_status({:error, _}), do: 500

  # Private helper functions

  defp string_to_error_atom(string) when is_binary(string) do
    normalized =
      string
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9_]/, "_")
      |> String.to_atom()

    # Map common string errors to standard atoms
    case normalized do
      :timeout -> :timeout
      :not_found -> :not_found
      :request_failed -> :request_failed
      :connection_refused -> :network_error
      _ -> normalized
    end
  rescue
    _ -> :unknown_error
  end

  defp log_exception(exception, stacktrace) do
    Logger.error("""
    Exception caught: #{Exception.format(:error, exception, stacktrace)}
    """)
  end

  defp log_retry(reason, attempt, max_attempts, delay) do
    Logger.debug("Retrying operation",
      reason: inspect(reason),
      attempt: attempt,
      max_attempts: max_attempts,
      retry_delay_ms: delay
    )
  end

  defp humanize_atom(atom) do
    atom
    |> to_string()
    |> String.replace("_", " ")
    |> String.capitalize()
  end

  # ══════════════════════════════════════════════════════════════════════════════
  # Safe Execution Helpers - Added to consolidate scattered try/rescue patterns
  # ══════════════════════════════════════════════════════════════════════════════

  @doc """
  Safely executes a function and returns normalized error tuples.
  Consolidates try/rescue patterns scattered throughout the codebase.

  ## Examples

      iex> safe_execute(fn -> {:ok, "success"} end)
      {:ok, "success"}

      iex> safe_execute(fn -> raise "error" end)
      {:error, :execution_error}

      iex> safe_execute(fn -> raise "error" end, fallback: "safe value")
      {:ok, "safe value"}
  """
  @spec safe_execute((-> any()), keyword()) :: result()
  def safe_execute(fun, opts \\ []) when is_function(fun, 0) do
    fallback = Keyword.get(opts, :fallback)
    error_context = Keyword.get(opts, :context, %{})
    log_errors = Keyword.get(opts, :log_errors, true)

    try do
      case fun.() do
        {:ok, _} = success -> success
        {:error, _} = error -> error
        result -> {:ok, result}
      end
    rescue
      exception ->
        error = {:error, :execution_error}
        enriched_error = enrich_error(error, Map.put(error_context, :exception, exception))

        if log_errors do
          log_error("Safe execution failed", elem(enriched_error, 1))
        end

        case fallback do
          nil -> enriched_error
          value -> {:ok, value}
        end
    end
  end

  @doc """
  Safely executes a function and returns a string result for user display.
  Consolidates string-returning error patterns in formatters and utilities.

  ## Examples

      iex> safe_execute_string(fn -> "success" end)
      "success"

      iex> safe_execute_string(fn -> raise "error" end, fallback: "Error occurred")
      "Error occurred"
  """
  @spec safe_execute_string((-> String.t()), keyword()) :: String.t()
  def safe_execute_string(fun, opts \\ []) when is_function(fun, 0) do
    fallback = Keyword.get(opts, :fallback, "Error occurred")

    case safe_execute(fun, opts) do
      {:ok, result} when is_binary(result) ->
        result

      {:ok, result} ->
        to_string(result)

      {:error, reason} ->
        case Keyword.get(opts, :use_error_message, false) do
          true -> format_error(reason)
          false -> fallback
        end
    end
  end

  @doc """
  Safely executes multiple operations and collects results.
  Useful for batch operations where some failures are acceptable.

  ## Examples

      iex> operations = [
      ...>   fn -> {:ok, "one"} end,
      ...>   fn -> raise "error" end,
      ...>   fn -> {:ok, "three"} end
      ...> ]
      iex> safe_execute_batch(operations)
      {:ok, ["one", "three"]}
  """
  @spec safe_execute_batch([(-> any())], keyword()) :: {:ok, [any()]} | {:error, :all_failed}
  def safe_execute_batch(functions, opts \\ []) when is_list(functions) do
    fail_fast = Keyword.get(opts, :fail_fast, false)

    results =
      functions
      |> Enum.reduce_while([], fn fun, acc ->
        case safe_execute(fun, opts) do
          {:ok, result} ->
            {:cont, [result | acc]}

          {:error, _reason} when fail_fast ->
            {:halt, {:error, :batch_failed}}

          {:error, _reason} ->
            {:cont, acc}
        end
      end)

    case results do
      {:error, _} = error ->
        error

      results when is_list(results) and length(results) > 0 ->
        {:ok, Enum.reverse(results)}

      [] ->
        {:error, :all_failed}
    end
  end
end
