defmodule WandererNotifier.Utils.ErrorHandler do
  @moduledoc """
  Common error handling and formatting utilities.

  Provides standardized error handling patterns used throughout the application:
  - Error message formatting
  - HTTP error handling  
  - Error logging with context
  - JSON operation error handling
  - Timeout wrapping
  """

  alias WandererNotifier.Logger.Logger, as: AppLogger

  @doc """
  Formats error reasons into human-readable messages.

  ## Examples

      iex> ErrorHandler.format_error_reason(:timeout)
      "Request timed out"
      
      iex> ErrorHandler.format_error_reason({:http_error, 404})
      "HTTP error: 404 Not Found"
      
      iex> ErrorHandler.format_error_reason(:rate_limited)
      "Rate limit exceeded"
  """
  @spec format_error_reason(atom() | tuple() | binary()) :: binary()
  def format_error_reason(:timeout), do: "Request timed out"
  def format_error_reason(:rate_limited), do: "Rate limit exceeded"
  def format_error_reason(:not_found), do: "Resource not found"
  def format_error_reason(:invalid_json), do: "Invalid JSON response"
  def format_error_reason(:invalid_response), do: "Invalid response format"
  def format_error_reason(:network_error), do: "Network connection error"
  def format_error_reason(:unauthorized), do: "Unauthorized access"
  def format_error_reason(:forbidden), do: "Access forbidden"
  def format_error_reason(:service_unavailable), do: "Service temporarily unavailable"

  def format_error_reason({:http_error, status}) when is_integer(status) do
    "HTTP error: #{status} #{status_code_to_text(status)}"
  end

  def format_error_reason({:missing_fields, fields}) when is_list(fields) do
    "Missing required fields: #{Enum.join(fields, ", ")}"
  end

  def format_error_reason({:validation_error, message}) when is_binary(message) do
    "Validation error: #{message}"
  end

  def format_error_reason(reason) when is_atom(reason) do
    "Error: #{reason}"
  end

  def format_error_reason(reason) when is_binary(reason) do
    reason
  end

  def format_error_reason(reason) do
    "Unexpected error: #{inspect(reason)}"
  end

  @doc """
  Creates a standardized error response tuple with optional context.

  ## Examples

      iex> ErrorHandler.create_error_response(:timeout)
      {:error, :timeout}
      
      iex> ErrorHandler.create_error_response(:http_error, %{status: 404, url: "/api/test"})
      {:error, {:http_error, %{status: 404, url: "/api/test"}}}
  """
  @spec create_error_response(atom() | tuple(), map() | nil) :: {:error, term()}
  def create_error_response(reason, context \\ nil)

  def create_error_response(reason, nil), do: {:error, reason}

  def create_error_response(reason, context) when is_map(context) do
    {:error, {reason, context}}
  end

  @doc """
  Handles HTTP responses with standardized error mapping.

  ## Examples

      iex> ErrorHandler.handle_http_response({:ok, %{status_code: 200, body: "{}"}})
      {:ok, "{}"}
      
      iex> ErrorHandler.handle_http_response({:ok, %{status_code: 404}})
      {:error, :not_found}
  """
  @spec handle_http_response({:ok, map()} | {:error, term()}) :: {:ok, term()} | {:error, term()}
  def handle_http_response({:ok, %{status_code: status, body: body}}) when status in 200..299 do
    {:ok, body}
  end

  def handle_http_response({:ok, %{status_code: 404}}) do
    {:error, :not_found}
  end

  def handle_http_response({:ok, %{status_code: 401}}) do
    {:error, :unauthorized}
  end

  def handle_http_response({:ok, %{status_code: 403}}) do
    {:error, :forbidden}
  end

  def handle_http_response({:ok, %{status_code: 429}}) do
    {:error, :rate_limited}
  end

  def handle_http_response({:ok, %{status_code: 503}}) do
    {:error, :service_unavailable}
  end

  def handle_http_response({:ok, %{status_code: status}}) when status >= 500 do
    {:error, {:http_error, status}}
  end

  def handle_http_response({:ok, %{status_code: status}}) do
    {:error, {:http_error, status}}
  end

  def handle_http_response({:error, reason}) do
    {:error, reason}
  end

  @doc """
  Logs an error with structured context metadata.

  ## Examples

      iex> ErrorHandler.log_error_with_context(:timeout, "API request failed", %{url: "/api/test"})
      :ok
  """
  @spec log_error_with_context(atom() | tuple(), binary(), map()) :: :ok
  def log_error_with_context(error_reason, message, context \\ %{})

  def log_error_with_context(error_reason, message, context) when is_map(context) do
    formatted_reason = format_error_reason(error_reason)

    AppLogger.error(
      message,
      Map.merge(context, %{
        error_reason: error_reason,
        error_message: formatted_reason
      })
    )
  end

  @doc """
  Normalizes error tuples to a consistent format.

  ## Examples

      iex> ErrorHandler.normalize_error_tuple({:error, :timeout})
      {:error, :timeout}
      
      iex> ErrorHandler.normalize_error_tuple({:err, "Something failed"})  
      {:error, "Something failed"}
  """
  @spec normalize_error_tuple(tuple()) :: {:error, term()}
  def normalize_error_tuple({:error, reason}), do: {:error, reason}
  def normalize_error_tuple({:err, reason}), do: {:error, reason}
  def normalize_error_tuple({:failure, reason}), do: {:error, reason}
  def normalize_error_tuple(other), do: {:error, other}

  @doc """
  Wraps a function call with timeout handling.

  ## Examples

      iex> ErrorHandler.timeout_wrapper(fn -> :ok end, 5000)
      {:ok, :ok}
      
      iex> ErrorHandler.timeout_wrapper(fn -> Process.sleep(6000); :ok end, 5000)
      {:error, :timeout}
  """
  @spec timeout_wrapper(function(), pos_integer()) :: {:ok, term()} | {:error, :timeout}
  def timeout_wrapper(fun, timeout_ms) when is_function(fun, 0) and is_integer(timeout_ms) do
    # Use supervised task to ensure proper cleanup
    task = Task.Supervisor.async(WandererNotifier.TaskSupervisor, fun)

    case Task.yield(task, timeout_ms) do
      {:ok, result} ->
        {:ok, result}

      nil ->
        Task.shutdown(task, :brutal_kill)
        {:error, :timeout}
    end
  rescue
    exception ->
      {:error, {:exception, exception}}
  end

  @doc """
  Safely performs JSON operations with error handling.

  ## Examples

      iex> ErrorHandler.safe_json_operation(fn -> Jason.decode("{}") end)
      {:ok, %{}}
      
      iex> ErrorHandler.safe_json_operation(fn -> Jason.decode("invalid") end)
      {:error, :invalid_json}
  """
  @spec safe_json_operation(function()) :: {:ok, term()} | {:error, :invalid_json}
  def safe_json_operation(json_fun) when is_function(json_fun, 0) do
    case json_fun.() do
      {:ok, result} -> {:ok, result}
      {:error, _} -> {:error, :invalid_json}
      result -> {:ok, result}
    end
  rescue
    _ -> {:error, :invalid_json}
  end

  @doc """
  Chains error handling for `with` pipelines by extracting the first error.

  ## Examples

      iex> ErrorHandler.chain_errors([{:ok, 1}, {:ok, 2}, {:error, :failed}])
      {:error, :failed}
      
      iex> ErrorHandler.chain_errors([{:ok, 1}, {:ok, 2}])
      {:ok, [1, 2]}
  """
  @spec chain_errors(list({:ok, term()} | {:error, term()})) :: {:ok, list()} | {:error, term()}
  def chain_errors(results) when is_list(results) do
    case Enum.find(results, fn
           {:error, _} -> true
           _ -> false
         end) do
      {:error, reason} ->
        {:error, reason}

      nil ->
        values = Enum.map(results, fn {:ok, value} -> value end)
        {:ok, values}
    end
  end

  # Private helper functions

  defp status_code_to_text(200), do: "OK"
  defp status_code_to_text(201), do: "Created"
  defp status_code_to_text(204), do: "No Content"
  defp status_code_to_text(400), do: "Bad Request"
  defp status_code_to_text(401), do: "Unauthorized"
  defp status_code_to_text(403), do: "Forbidden"
  defp status_code_to_text(404), do: "Not Found"
  defp status_code_to_text(429), do: "Too Many Requests"
  defp status_code_to_text(500), do: "Internal Server Error"
  defp status_code_to_text(502), do: "Bad Gateway"
  defp status_code_to_text(503), do: "Service Unavailable"
  defp status_code_to_text(504), do: "Gateway Timeout"
  defp status_code_to_text(status), do: "Unknown (#{status})"
end
