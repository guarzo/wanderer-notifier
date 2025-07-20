defmodule WandererNotifier.Infrastructure.Http.ClientBase do
  @moduledoc """
  Base HTTP client module that provides common functionality for all HTTP clients.

  This module consolidates duplicate patterns across ESI, WandererKills, License, 
  and other HTTP clients, providing:

  - Unified request building
  - Consistent response handling
  - Default middleware configuration
  - Common headers management
  - Error handling patterns
  - Logging utilities

  ## Usage

      defmodule MyClient do
        use WandererNotifier.Infrastructure.Http.ClientBase,
          base_url: "https://api.example.com",
          timeout: 10_000,
          service_name: "my_service"
        
        def get_resource(id) do
          url = base_url() <> "/resources/" <> to_string(id)
          
          request(:get, url,
            headers: build_headers(),
            opts: build_default_opts()
          )
        end
      end
  """

  alias WandererNotifier.Shared.Logger.Logger, as: AppLogger
  alias WandererNotifier.Infrastructure.Http, as: HTTP
  alias WandererNotifier.Infrastructure.Http.ResponseHandler
  alias WandererNotifier.Shared.Utils.TimeUtils

  @doc """
  Macro to inject common HTTP client functionality into modules.
  """
  defmacro __using__(opts \\ []) do
    quote do
      alias WandererNotifier.Shared.Logger.Logger, as: AppLogger
      alias WandererNotifier.Infrastructure.Http, as: HTTP
      alias WandererNotifier.Infrastructure.Http.ResponseHandler
      alias WandererNotifier.Infrastructure.Http.ClientBase
      alias WandererNotifier.Shared.Utils.TimeUtils

      # Import common functions
      import ClientBase

      # Module attributes that can be overridden
      @base_url unquote(opts[:base_url])
      @default_timeout unquote(opts[:timeout]) || 15_000
      @default_recv_timeout unquote(opts[:recv_timeout]) || 15_000
      @service_name unquote(opts[:service_name]) || "http_service"

      # Default implementations that can be overridden
      def base_url, do: @base_url
      def default_timeout, do: @default_timeout
      def default_recv_timeout, do: @default_recv_timeout
      def service_name, do: @service_name

      defoverridable base_url: 0, default_timeout: 0, default_recv_timeout: 0, service_name: 0
    end
  end

  @doc """
  Makes an HTTP request with common patterns applied.

  ## Options
  - `:headers` - Additional headers to include
  - `:opts` - HTTP client options (timeouts, middleware config, etc.)
  - `:with_timing` - Whether to measure request timing (default: false)
  - `:log_context` - Additional context for logging
  """
  def request(method, url, options \\ []) do
    headers = Keyword.get(options, :headers, [])
    opts = Keyword.get(options, :opts, [])
    with_timing = Keyword.get(options, :with_timing, false)
    log_context = Keyword.get(options, :log_context, %{})
    body = Keyword.get(options, :body)

    if with_timing do
      make_timed_request(method, url, headers, body, opts, log_context)
    else
      make_request(method, url, headers, body, opts, log_context)
    end
  end

  @doc """
  Builds default options for HTTP requests with common middleware configuration.

  ## Parameters
  - `base_opts` - Base options to merge with
  - `config` - Configuration map with optional keys:
    - `:timeout` - Request timeout
    - `:recv_timeout` - Receive timeout
    - `:retry_options` - Retry middleware configuration
    - `:rate_limit_options` - Rate limiting configuration
    - `:telemetry_options` - Telemetry configuration
  """
  def build_default_opts(base_opts \\ [], config \\ %{}) do
    timeout = Map.get(config, :timeout, 15_000)
    recv_timeout = Map.get(config, :recv_timeout, 15_000)

    opts =
      Keyword.merge(base_opts,
        timeout: timeout,
        recv_timeout: recv_timeout
      )

    opts
    |> maybe_add_retry_options(config)
    |> maybe_add_rate_limit_options(config)
    |> maybe_add_telemetry_options(config)
  end

  @doc """
  Handles HTTP responses with common patterns.

  ## Options
  - `:success_codes` - Range or list of successful status codes (default: 200..299)
  - `:custom_handlers` - List of {status_code, handler_fn} tuples
  - `:resource_type` - Type of resource being requested (for logging)
  - `:context` - Additional context for logging
  """
  def handle_response(response, options \\ []) do
    success_codes = Keyword.get(options, :success_codes, 200..299)
    custom_handlers = Keyword.get(options, :custom_handlers, [])
    resource_type = Keyword.get(options, :resource_type, "resource")
    context = Keyword.get(options, :context, %{})

    log_context =
      Map.merge(context, %{
        resource_type: resource_type
      })

    ResponseHandler.handle_response(response,
      success_codes: success_codes,
      custom_handlers: custom_handlers,
      log_context: log_context
    )
  end

  @doc """
  Creates a timing wrapper for HTTP requests.
  """
  def with_timing(request_fn) do
    {result, duration_ms} = TimeUtils.measure(request_fn)

    case result do
      {:ok, response} ->
        {:ok, response}

      {:error, reason} when is_map(reason) ->
        {:error, Map.put_new(reason, :duration_ms, duration_ms)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Builds common headers for API requests.
  """
  def build_headers(custom_headers \\ [], options \\ []) do
    base_headers = [
      {"Content-Type", "application/json"},
      {"Accept", "application/json"}
    ]

    user_agent = Keyword.get(options, :user_agent, "WandererNotifier/1.0")

    headers = base_headers ++ [{"User-Agent", user_agent}]

    # Add any custom headers
    headers ++ custom_headers
  end

  @doc """
  Logs API debug information in a consistent format.
  """
  def log_api_debug(message, metadata) do
    AppLogger.api_debug(message, metadata)
  end

  @doc """
  Logs API errors in a consistent format.
  """
  def log_api_error(message, metadata) do
    AppLogger.api_error(message, metadata)
  end

  @doc """
  Logs API info in a consistent format.
  """
  def log_api_info(message, metadata) do
    AppLogger.api_info(message, metadata)
  end

  @doc """
  Decodes JSON response body with error handling.
  """
  def decode_json_response(body) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, decoded} -> {:ok, decoded}
      {:error, reason} -> {:error, {:json_decode_error, reason}}
    end
  end

  def decode_json_response(data), do: {:ok, data}

  # Private functions

  defp make_request(method, url, headers, body, opts, _log_context) do
    case method do
      :get -> HTTP.get(url, headers, opts)
      :post -> HTTP.post(url, body, headers, opts)
      :put -> HTTP.request(:put, url, headers, body, opts)
      :delete -> HTTP.request(:delete, url, headers, body, opts)
      _ -> {:error, :unsupported_method}
    end
  end

  defp make_timed_request(method, url, headers, body, opts, log_context) do
    with_timing(fn ->
      make_request(method, url, headers, body, opts, log_context)
    end)
  end

  defp maybe_add_retry_options(opts, %{retry_options: retry_options}) do
    Keyword.put(opts, :retry_options, retry_options)
  end

  defp maybe_add_retry_options(opts, _), do: opts

  defp maybe_add_rate_limit_options(opts, %{rate_limit_options: rate_limit_options}) do
    Keyword.put(opts, :rate_limit_options, rate_limit_options)
  end

  defp maybe_add_rate_limit_options(opts, _), do: opts

  defp maybe_add_telemetry_options(opts, %{telemetry_options: telemetry_options}) do
    Keyword.put(opts, :telemetry_options, telemetry_options)
  end

  defp maybe_add_telemetry_options(opts, _), do: opts
end
