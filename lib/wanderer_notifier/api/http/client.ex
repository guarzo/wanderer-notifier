defmodule WandererNotifier.Api.Http.Client do
  @moduledoc """
  Generic HTTP client wrapper with consistent error handling and retry functionality.
  Provides a unified interface for making HTTP requests across the application.
  """
  require Logger

  @default_max_retries 3
  @default_initial_backoff 500  # milliseconds
  @default_max_backoff 5000     # milliseconds
  @default_timeout 10000        # milliseconds (10 seconds)

  # Errors that are considered transient and can be retried
  @transient_errors [:timeout, :connect_timeout, :econnrefused, :closed, :enetunreach, :system_limit]

  @doc """
  Makes a GET request to the specified URL.

  ## Options
    - Same as `request/5`

  ## Returns
    - `{:ok, %{status_code: status, body: body, headers: headers}}` on success
    - `{:error, reason}` on failure
  """
  def get(url, headers \\ [], opts \\ []) do
    request("GET", url, headers, "", opts)
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
  def request(method, url, headers \\ [], body \\ "", opts \\ []) do
    max_retries = Keyword.get(opts, :max_retries, @default_max_retries)
    initial_backoff = Keyword.get(opts, :initial_backoff, @default_initial_backoff)
    timeout = Keyword.get(opts, :timeout, @default_timeout)
    label = Keyword.get(opts, :label, url)

    # Log the request at debug level
    if Keyword.get(opts, :debug, false) do
      log_request_debug(method, url, headers, body)
    end

    # Asynchronously handle the request with retries
    task = Task.async(fn ->
      do_request_with_retry(method, url, headers, body, max_retries, initial_backoff, 0, label, timeout)
    end)

    # Wait for the result with timeout
    try do
      Task.await(task, timeout * (max_retries + 1))
    catch
      :exit, {:timeout, _} ->
        Logger.error("HTTP request timed out: #{method} #{url}")
        Task.shutdown(task, :brutal_kill)
        {:error, :timeout}
    end
  end

  # Execute the request with retry logic
  defp do_request_with_retry(method, url, headers, body, max_retries, backoff, retry_count, label, timeout) do
    options = [
      hackney: [
        follow_redirect: true,
        recv_timeout: timeout,
        connect_timeout: div(timeout, 2)
      ]
    ]

    method_str = to_string(method) |> String.upcase()

    case HTTPoison.request(method, url, body, headers, options) do
      {:ok, response = %{status_code: status_code}} ->
        # Only log at debug level for successful responses
        Logger.debug("HTTP #{method_str} [#{label}] => status #{status_code}")

        # Return a consistent response format
        {:ok, %{
          status_code: response.status_code,
          body: response.body,
          headers: response.headers
        }}

      {:error, %HTTPoison.Error{reason: reason}} ->
        # Determine if we should retry
        if retry_count < max_retries and transient_error?(reason) do
          # Calculate exponential backoff with jitter
          current_backoff = min(backoff * :math.pow(2, retry_count), @default_max_backoff)
          jitter = :rand.uniform(trunc(current_backoff * 0.2))
          actual_backoff = trunc(current_backoff + jitter)

          Logger.warning(
            "HTTP #{method_str} [#{label}] failed: #{inspect(reason)}. Retrying in #{actual_backoff}ms (attempt #{retry_count + 1}/#{max_retries})"
          )

          :timer.sleep(actual_backoff)
          do_request_with_retry(method, url, headers, body, max_retries, backoff, retry_count + 1, label, timeout)
        else
          log_level = if retry_count > 0, do: :error, else: :warning
          logger_fn = case log_level do
            :error -> &Logger.error/1
            :warning -> &Logger.warning/1
            _ -> &Logger.debug/1
          end

          logger_fn.("HTTP #{method_str} [#{label}] failed#{if retry_count > 0, do: " after #{retry_count + 1} attempts", else: ""}: #{inspect(reason)}")

          # Consider all HTTP errors as recoverable for the caller
          {:error, reason}
        end
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
    body_str = cond do
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
      Enum.map(headers, fn {k, v} ->
        ~s(-H "#{k}: #{v}")
      end)
      |> Enum.join(" ")

    body_str = if body && body != "", do: ~s(--data '#{body}'), else: ""

    ~s(curl -X #{method_str} #{header_str} #{body_str} "#{url}")
  end

  @doc """
  Handles response status codes appropriately, converting them to meaningful atoms.

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

  def handle_response({:ok, %{status_code: status, body: body}}, decode_json) do
    case status do
      code when code in 200..299 ->
        if decode_json do
          case Jason.decode(body) do
            {:ok, parsed} -> {:ok, parsed}
            {:error, _reason} -> {:error, :invalid_json}
          end
        else
          {:ok, body}
        end

      401 -> {:error, :unauthorized}
      403 -> {:error, :forbidden}
      404 -> {:error, :not_found}
      429 -> {:error, :rate_limited}

      code when code in 500..599 ->
        {:error, :server_error}

      _ ->
        {:error, {:unexpected_status, status}}
    end
  end

  def handle_response({:error, reason}, _decode_json) do
    {:error, reason}
  end
end
