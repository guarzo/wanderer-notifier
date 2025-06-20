defmodule WandererNotifier.HTTP do
  @moduledoc """
  Unified HTTP client module that handles all HTTP operations for the application.
  Provides a single interface for making HTTP requests with built-in retry logic,
  timeout management, and error handling.
  """
  @behaviour WandererNotifier.HTTP.HttpBehaviour

  alias WandererNotifier.Constants
  alias WandererNotifier.Http.Utils.JsonUtils
  alias WandererNotifier.Utils.TimeUtils
  alias WandererNotifier.Logger.Logger, as: AppLogger

  use WandererNotifier.Logger.ApiLoggerMacros

  @type url :: String.t()
  @type headers :: list({String.t(), String.t()})
  @type opts :: keyword()
  @type body :: String.t() | map()
  @type method :: :get | :post | :put | :delete | :head | :options
  @type response :: {:ok, %{status_code: integer(), body: term()}} | {:error, term()}

  @default_headers [{"Content-Type", "application/json"}]
  @default_get_headers []
  @default_timeout Constants.default_timeout()
  @default_recv_timeout Constants.default_recv_timeout()
  @default_connect_timeout Constants.default_connect_timeout()
  @default_pool_timeout Constants.default_pool_timeout()

  @doc """
  Makes a GET request to the specified URL.
  """
  @spec get(url(), headers(), opts()) :: response()
  def get(url, headers \\ @default_get_headers, opts \\ []) do
    request(:get, url, headers, nil, opts)
  end

  @doc """
  Makes a POST request with the given body.
  """
  @spec post(url(), body(), headers(), opts()) :: response()
  def post(url, body, headers \\ @default_headers, opts \\ []) do
    request(:post, url, headers, body, opts)
  end

  @doc """
  Makes a POST request with JSON body.
  """
  @spec post_json(url(), map(), headers(), opts()) :: response()
  def post_json(url, body, headers \\ @default_headers, opts \\ []) do
    encoded_body = JsonUtils.encode!(body)
    post(url, encoded_body, headers, opts)
  end

  @doc """
  Makes a generic HTTP request with retry logic and error handling.
  """
  @spec request(method(), url(), headers(), body() | nil, opts()) :: response()
  def request(method, url, headers, body, opts) do
    start_time = TimeUtils.monotonic_ms()

    case make_request(method, url, headers, body, opts) do
      {:ok, response} ->
        result = process_response(response, url, method)

        case result do
          {:ok, %{status_code: status}} -> log_success(method, url, status, start_time)
        end

        result

      {:error, %HTTPoison.Error{reason: reason}} ->
        log_error(method, url, reason, start_time)
        {:error, reason}
    end
  end

  # Private implementation

  defp make_request(method, url, headers, body, opts) do
    payload = prepare_body(body)
    request_opts = build_request_opts(opts)

    HTTPoison.request(method, url, payload, headers, request_opts)
  end

  defp prepare_body(nil), do: ""
  defp prepare_body(body) when is_map(body), do: JsonUtils.encode!(body)
  defp prepare_body(body), do: body

  defp build_request_opts(opts) do
    [
      timeout: Keyword.get(opts, :timeout, @default_timeout),
      recv_timeout: Keyword.get(opts, :recv_timeout, @default_recv_timeout),
      connect_timeout: Keyword.get(opts, :connect_timeout, @default_connect_timeout),
      pool_timeout: Keyword.get(opts, :pool_timeout, @default_pool_timeout),
      hackney: [pool: :default]
    ]
  end

  @spec process_response(HTTPoison.Response.t(), url(), method()) :: response()
  defp process_response(%HTTPoison.Response{status_code: status, body: body}, _url, _method) do
    processed_body =
      case JsonUtils.decode(body) do
        {:ok, decoded} -> decoded
        {:error, _reason} -> body
      end

    if status >= 400 do
      {:error, {:http_error, status, processed_body}}
    else
      {:ok, %{status_code: status, body: processed_body}}
    end
  end

  defp log_success(method, url, status, start_time) do
    duration_ms = TimeUtils.monotonic_ms() - start_time
    log_api_success(url, status, duration_ms, %{method: method, client: "HTTP"})
  end

  defp log_error(method, url, reason, start_time) do
    duration_ms = TimeUtils.monotonic_ms() - start_time
    # Explicitly pass duration_ms as the third parameter (not nil)
    # The macro handles both nil and non-nil cases, but we always have a value
    metadata = Map.put(%{method: method, client: "HTTP"}, :duration_ms, duration_ms)

    AppLogger.api_error(
      "API request failed",
      Map.merge(metadata, %{
        url: url,
        error: inspect(reason)
      })
    )
  end

  @doc """
  Makes a GET request to the ZKill API for a specific killmail.
  Requires both the killmail ID and hash for proper identification.

  ## Parameters
    - killmail_id: The ID of the killmail
    - hash: The hash of the killmail

  ## Returns
    - {:ok, response} on success
    - {:error, reason} on failure
  """
  @spec get_killmail(integer(), String.t()) :: response()
  def get_killmail(killmail_id, hash) do
    url = build_url(killmail_id, hash)
    get(url)
  end

  @spec build_url(integer(), String.t()) :: String.t()
  defp build_url(killmail_id, hash) do
    "https://zkillboard.com/api/killID/#{killmail_id}/#{hash}/"
  end
end
