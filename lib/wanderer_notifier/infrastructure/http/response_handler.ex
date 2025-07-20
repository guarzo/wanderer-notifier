defmodule WandererNotifier.Infrastructure.Http.ResponseHandler do
  @moduledoc """
  Unified HTTP response handler for consistent response processing across the application.

  Provides a flexible way to handle HTTP responses with:
  - Configurable success status codes
  - Custom handling for specific status codes
  - Consistent error formats
  - Integrated logging
  """

  require Logger

  @type response :: {:ok, term()} | {:error, term()}
  @type status_code :: non_neg_integer()
  @type body :: term()
  @type reason :: term()

  @type options :: [
          success_codes: status_code() | Range.t() | [status_code()],
          custom_handlers: [{status_code() | Range.t(), handler_fun}],
          error_format: :tuple | :string,
          log_context: map(),
          parse_json: boolean()
        ]

  @type handler_fun :: (status_code(), body() -> response())

  @doc """
  Handles HTTP responses with configurable options.

  ## Options

    * `:success_codes` - Status code(s) considered successful. Default: 200
    * `:custom_handlers` - List of {status_code, handler_function} tuples for custom handling
    * `:error_format` - Format for error responses (:tuple or :string). Default: :tuple
    * `:log_context` - Additional context for logging. Default: %{}
    * `:parse_json` - Whether to parse JSON body on success. Default: false

  ## Examples

      # Basic usage
      handle_response({:ok, %{status_code: 200, body: data}})
      
      # With custom 404 handling
      handle_response({:ok, %{status_code: 404, body: ""}}, 
        custom_handlers: [{404, fn _, _ -> {:error, :not_found} end}]
      )
      
      # With success range
      handle_response({:ok, %{status_code: 201, body: data}}, 
        success_codes: 200..299
      )
  """
  @spec handle_response(
          {:ok, %{status_code: status_code(), body: body()}} | {:error, reason()},
          options()
        ) :: response()
  def handle_response(response, opts \\ [])

  def handle_response({:ok, %{status_code: status_code, body: body}}, opts) do
    success_codes = Keyword.get(opts, :success_codes, 200)
    custom_handlers = Keyword.get(opts, :custom_handlers, [])
    log_context = Keyword.get(opts, :log_context, %{})
    parse_json = Keyword.get(opts, :parse_json, false)

    cond do
      # Check custom handlers first
      handler = find_custom_handler(status_code, custom_handlers) ->
        handler.(status_code, body)

      # Check success codes
      matches_success_code?(status_code, success_codes) ->
        handle_success(body, parse_json, status_code, log_context)

      # Default error handling
      true ->
        handle_http_error(status_code, body, opts)
    end
  end

  def handle_response({:error, :timeout}, opts) do
    log_context = Keyword.get(opts, :log_context, %{})

    Logger.warning("Request timeout",
      context: Map.merge(log_context, %{error: :timeout})
    )

    format_error(:timeout, opts)
  end

  def handle_response({:error, {:timeout, _} = reason}, opts) do
    log_context = Keyword.get(opts, :log_context, %{})

    Logger.warning("Request timeout",
      context: Map.merge(log_context, %{error: reason})
    )

    format_error(:timeout, opts)
  end

  def handle_response({:error, :connect_timeout}, opts) do
    log_context = Keyword.get(opts, :log_context, %{})

    Logger.warning("Connection timeout",
      context: Map.merge(log_context, %{error: :connect_timeout})
    )

    format_error(:connect_timeout, opts)
  end

  # Handle the new HTTP error format from WandererNotifier.HTTP
  def handle_response({:error, {:http_error, status_code, body}}, opts) do
    log_context = Keyword.get(opts, :log_context, %{})
    custom_handlers = Keyword.get(opts, :custom_handlers, [])

    # Check if there's a custom handler for this status code
    if handler = find_custom_handler(status_code, custom_handlers) do
      handler.(status_code, body)
    else
      Logger.warning("HTTP error response",
        context: Map.merge(log_context, %{status_code: status_code})
      )

      handle_http_error(status_code, body, opts)
    end
  end

  def handle_response({:error, reason}, opts) do
    log_context = Keyword.get(opts, :log_context, %{})

    Logger.error("Request failed",
      context: Map.merge(log_context, %{error: reason})
    )

    format_error(reason, opts)
  end

  @doc """
  Creates a custom handler for 404 responses that returns {:error, :not_found}.
  """
  @spec not_found_handler() :: {404, handler_fun()}
  def not_found_handler do
    {404, fn _status, _body -> {:error, :not_found} end}
  end

  @doc """
  Creates a custom handler for 404 responses with logging.
  """
  @spec not_found_handler(map()) :: {404, handler_fun()}
  def not_found_handler(log_context) do
    {404,
     fn _status, _body ->
       Logger.info("Resource not found",
         context: Map.merge(log_context, %{status: 404})
       )

       {:error, :not_found}
     end}
  end

  # Private functions

  defp find_custom_handler(status_code, handlers) do
    Enum.find_value(handlers, fn
      {code, handler} when is_integer(code) and code == status_code ->
        handler

      {%Range{} = range, handler} ->
        if status_code in range, do: handler

      _ ->
        nil
    end)
  end

  defp matches_success_code?(status_code, success_codes) do
    case success_codes do
      code when is_integer(code) ->
        status_code == code

      %Range{} = range ->
        status_code in range

      codes when is_list(codes) ->
        status_code in codes
    end
  end

  defp handle_success(body, true, status_code, log_context) do
    case Jason.decode(body) do
      {:ok, parsed} ->
        Logger.debug("Request successful",
          context: Map.merge(log_context, %{status: status_code})
        )

        {:ok, parsed}

      {:error, reason} ->
        Logger.error("Failed to parse JSON response",
          context:
            Map.merge(log_context, %{
              status: status_code,
              error: reason,
              body: String.slice(body, 0, 200)
            })
        )

        {:error, {:json_decode_error, reason}}
    end
  end

  defp handle_success(body, false, status_code, log_context) do
    Logger.debug("Request successful",
      context: Map.merge(log_context, %{status: status_code})
    )

    {:ok, body}
  end

  defp handle_http_error(status_code, body, opts) do
    log_context = Keyword.get(opts, :log_context, %{})

    Logger.warning("HTTP error response",
      context:
        Map.merge(log_context, %{
          status: status_code,
          body: String.slice(to_string(body), 0, 200)
        })
    )

    case Keyword.get(opts, :error_format, :tuple) do
      :string ->
        {:error, "HTTP error: #{status_code}"}

      :tuple ->
        {:error, {:http_error, status_code}}
    end
  end

  defp format_error(reason, opts) do
    case Keyword.get(opts, :error_format, :tuple) do
      :string ->
        {:error, "Request error: #{inspect(reason)}"}

      :tuple ->
        {:error, reason}
    end
  end
end
