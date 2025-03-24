defmodule WandererNotifier.Api.Http.Client do
  @moduledoc """
  Generic HTTP client wrapper with consistent error handling and retry functionality.
  Provides a unified interface for making HTTP requests across the application.
  """
  @behaviour WandererNotifier.Api.Http.ClientBehaviour

  require Logger
  alias WandererNotifier.Logger, as: AppLogger

  @default_max_retries 3
  # milliseconds
  @default_initial_backoff 500
  # milliseconds
  @default_max_backoff 5000
  # milliseconds (10 seconds)
  @default_timeout 10_000

  # Errors that are considered transient and can be retried
  @transient_errors [
    :timeout,
    :connect_timeout,
    :econnrefused,
    :closed,
    :enetunreach,
    :system_limit
  ]

  @doc """
  Makes a GET request to the specified URL.

  ## Parameters
    - `url` - The URL to send the request to
    - `headers` - List of HTTP headers
    - `opts` - Options for the request

  ## Options
    - `:query` - Map of query parameters to be appended to the URL
    - Same as `request/5`

  ## Returns
    - `{:ok, %{status_code: status, body: body, headers: headers}}` on success
    - `{:error, reason}` on failure
  """
  @impl WandererNotifier.Api.Http.ClientBehaviour
  def get(url, headers \\ [], opts \\ []) do
    url_with_query =
      case Keyword.get(opts, :query) do
        nil ->
          url

        query when is_map(query) ->
          # Build the query string from the map
          query_string = URI.encode_query(query)

          if String.contains?(url, "?") do
            "#{url}&#{query_string}"
          else
            "#{url}?#{query_string}"
          end

        _ ->
          url
      end

    request("GET", url_with_query, headers, "", opts)
  end

  @doc """
  Makes a POST request to the specified URL.

  ## Options
    - Same as `request/5`

  ## Returns
    - `{:ok, %{status_code: status, body: body, headers: headers}}` on success
    - `{:error, reason}` on failure
  """
  @impl WandererNotifier.Api.Http.ClientBehaviour
  def post(url, body, headers \\ [], opts \\ []) do
    request("POST", url, headers, body, opts)
  end

  @doc """
  Makes a PUT request to the specified URL.

  ## Options
    - Same as `request/5`

  ## Returns
    - `{:ok, %{status_code: status, body: body, headers: headers}}` on success
    - `{:error, reason}` on failure
  """
  @impl WandererNotifier.Api.Http.ClientBehaviour
  def put(url, body, headers \\ [], opts \\ []) do
    request("PUT", url, headers, body, opts)
  end

  @doc """
  Makes a DELETE request to the specified URL.

  ## Options
    - Same as `request/5`

  ## Returns
    - `{:ok, %{status_code: status, body: body, headers: headers}}` on success
    - `{:error, reason}` on failure
  """
  @impl WandererNotifier.Api.Http.ClientBehaviour
  def delete(url, headers \\ [], opts \\ []) do
    request("DELETE", url, headers, "", opts)
  end

  @doc """
  Makes a POST request with JSON data to the specified URL.
  Automatically sets the Content-Type header to application/json.

  ## Options
    - Same as `request/5`

  ## Returns
    - `{:ok, %{status_code: status, body: body, headers: headers}}` on success
    - `{:error, reason}` on failure
  """
  @impl WandererNotifier.Api.Http.ClientBehaviour
  def post_json(url, data, headers \\ [], opts \\ []) do
    json_data = Jason.encode!(data)
    json_headers = [{"Content-Type", "application/json"} | headers]
    request("POST", url, json_headers, json_data, opts)
  end

  @doc """
  Makes an HTTP request to the specified URL.

  ## Options
    - `:max_retries` - maximum number of retries (default: #{@default_max_retries})
    - `:initial_backoff` - initial backoff time in milliseconds (default: #{@default_initial_backoff})
    - `:label` - label for logging purposes (default: the URL)
    - `:timeout` - request timeout in milliseconds (default: #{@default_timeout})

  ## Returns
    - `{:ok, %{status_code: status, body: body, headers: headers}}` on success
    - `{:error, reason}` on failure
  """
  @impl WandererNotifier.Api.Http.ClientBehaviour
  def request(method, url, headers \\ [], body \\ "", opts \\ []) do
    max_retries = Keyword.get(opts, :max_retries, @default_max_retries)
    initial_backoff = Keyword.get(opts, :initial_backoff, @default_initial_backoff)
    timeout = Keyword.get(opts, :timeout, @default_timeout)
    label = Keyword.get(opts, :label, url)

    # Log the request at debug level
    if Keyword.get(opts, :debug, false) do
      log_request_debug(method, url, headers, body)
    end

    # Create request config to reduce arity
    request_config = %{
      max_retries: max_retries,
      initial_backoff: initial_backoff,
      timeout: timeout,
      label: label
    }

    # Asynchronously handle the request with retries
    task =
      Task.async(fn ->
        do_request_with_retry(
          method,
          url,
          headers,
          body,
          request_config,
          0
        )
      end)

    # Wait for the result with timeout
    try do
      Task.await(task, timeout * (max_retries + 1))
    catch
      :exit, {:timeout, _} ->
        AppLogger.api_error("HTTP request timed out: #{method} #{url}")
        Task.shutdown(task, :brutal_kill)
        {:error, :timeout}
    end
  end

  # Execute the request with retry logic
  # Reduced parameters by using a config map
  defp do_request_with_retry(
         method,
         url,
         headers,
         body,
         config,
         retry_count
       ) do
    options = [
      hackney: [
        follow_redirect: true,
        recv_timeout: config.timeout,
        connect_timeout: div(config.timeout, 2)
      ]
    ]

    method_str = to_string(method) |> String.upcase()

    case HTTPoison.request(method, url, body, headers, options) do
      {:ok, response = %{status_code: status_code}} ->
        # Only log at debug level for successful responses
        AppLogger.api_debug("HTTP #{method_str} [#{config.label}] => status #{status_code}")

        # Return a consistent response format
        {:ok,
         %{
           status_code: response.status_code,
           body: response.body,
           headers: response.headers
         }}

      {:error, %HTTPoison.Error{reason: reason}} ->
        handle_request_error(
          method_str,
          url,
          headers,
          body,
          config,
          retry_count,
          reason
        )
    end
  end

  # Handle request errors and implement retry logic
  # This reduces the nesting depth in do_request_with_retry
  defp handle_request_error(
         method_str,
         url,
         headers,
         body,
         config,
         retry_count,
         reason
       ) do
    # Determine if we should retry
    if retry_count < config.max_retries and transient_error?(reason) do
      # Calculate exponential backoff with jitter
      current_backoff =
        min(config.initial_backoff * :math.pow(2, retry_count), @default_max_backoff)

      jitter = :rand.uniform(trunc(current_backoff * 0.2))
      actual_backoff = trunc(current_backoff + jitter)

      Logger.warning(
        "HTTP #{method_str} [#{config.label}] failed: #{inspect(reason)}. Retrying in #{actual_backoff}ms (attempt #{retry_count + 1}/#{config.max_retries})"
      )

      :timer.sleep(actual_backoff)

      do_request_with_retry(
        method_str,
        url,
        headers,
        body,
        config,
        retry_count + 1
      )
    else
      log_request_failure(method_str, config.label, retry_count, reason)
      # Consider all HTTP errors as recoverable for the caller
      {:error, reason}
    end
  end

  # Log request failures, further simplifying the error handling
  defp log_request_failure(method_str, label, retry_count, reason) do
    log_level = if retry_count > 0, do: :error, else: :warning

    message =
      "HTTP #{method_str} [#{label}] failed" <>
        if(retry_count > 0, do: " after #{retry_count + 1} attempts", else: "") <>
        ": #{inspect(reason)}"

    case log_level do
      :error -> AppLogger.api_error(message)
      :warning -> AppLogger.api_warn(message)
      _ -> AppLogger.api_debug(message)
    end
  end

  # Determine if an error is transient and can be retried
  defp transient_error?(reason) when reason in @transient_errors, do: true
  defp transient_error?({:closed, _}), do: true
  defp transient_error?({:timeout, _}), do: true
  defp transient_error?(:timeout), do: true
  defp transient_error?(_), do: false

  # Log detailed request information at debug level
  defp log_request_debug(method, url, headers, body) do
    method_str = to_string(method) |> String.upcase()

    # Format the request details for logging
    headers_str = Enum.map_join(headers, "\n  ", fn {k, v} -> "#{k}: #{v}" end)

    # Truncate and sanitize body for logging
    body_str =
      cond do
        is_binary(body) and byte_size(body) > 1000 ->
          "#{String.slice(body, 0..999)}... [truncated, #{byte_size(body)} bytes total]"

        is_binary(body) ->
          body

        true ->
          inspect(body)
      end

    Logger.debug("""
    HTTP Request:
      #{method_str} #{url}
      Headers:
        #{headers_str}
      Body:
        #{body_str}
    """)
  end

  @doc """
  Builds a sample curl command for debugging or logging.
  """
  def build_curl_command(method, url, headers \\ [], body \\ nil) do
    method_str = to_string(method) |> String.upcase()

    header_str =
      Enum.map_join(headers, " ", fn {k, v} ->
        ~s(-H "#{k}: #{v}")
      end)

    body_str = if body && body != "", do: ~s(--data '#{body}'), else: ""

    ~s(curl -X #{method_str} #{header_str} #{body_str} "#{url}")
  end

  @doc """
  Handles response status codes appropriately, converting them to meaningful atoms.
  This is a convenience wrapper around WandererNotifier.Api.Http.ResponseHandler.

  ## Examples:
    - 200-299: {:ok, parsed_body}
    - 401: {:error, :unauthorized}
    - 403: {:error, :forbidden}
    - 404: {:error, :not_found}
    - 429: {:error, :rate_limited}
    - 500-599: {:error, :server_error}
    - Others: {:error, {:unexpected_status, status}}
  """
  def handle_response(response, decode_json \\ true)

  def handle_response({:ok, %{status_code: status, body: body}} = response, decode_json) do
    # Log curl command example for debugging when needed
    curl_example =
      case response do
        {:ok, %{request: %{method: method, url: url, headers: headers, body: body}}} ->
          build_curl_command(method, url, headers, body)

        _ ->
          "n/a"
      end

    if decode_json and status in 200..299 do
      # Forward to ResponseHandler which can handle JSON responses consistently
      WandererNotifier.Api.Http.ResponseHandler.handle_response(response, curl_example)
    else
      handle_response_by_status(status, body, decode_json)
    end
  end

  def handle_response({:error, reason}, _decode_json) do
    {:error, reason}
  end

  # Split out the status code handling to reduce complexity and nesting
  defp handle_response_by_status(status, body, decode_json) do
    case status do
      code when code in 200..299 ->
        handle_success_response(body, decode_json)

      401 ->
        {:error, :unauthorized}

      403 ->
        {:error, :forbidden}

      404 ->
        {:error, :not_found}

      429 ->
        {:error, :rate_limited}

      code when code in 500..599 ->
        {:error, :server_error}

      _ ->
        {:error, {:unexpected_status, status}}
    end
  end

  # Handle success response with optional JSON parsing
  defp handle_success_response(body, true) do
    case Jason.decode(body) do
      {:ok, parsed} -> {:ok, parsed}
      {:error, _reason} -> {:error, :invalid_json}
    end
  end

  defp handle_success_response(body, false) do
    {:ok, body}
  end
end
