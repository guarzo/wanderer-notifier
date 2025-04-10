defmodule WandererNotifier.Api.Http.Client do
  @moduledoc """
  Generic HTTP client wrapper with consistent error handling and retry functionality.
  Provides a unified interface for making HTTP requests across the application.
  """
  @behaviour WandererNotifier.Api.Http.ClientBehaviour

  alias WandererNotifier.Api.Http.ResponseHandler
  alias WandererNotifier.Logger.Logger, as: AppLogger

  @transient_errors [
    :timeout,
    :connect_timeout,
    :econnrefused,
    :closed,
    :enetunreach,
    :system_limit,
    :rate_limited,
    {:domain_error, :map, :rate_limited},
    {:domain_error, :esi, :rate_limited},
    {:domain_error, :zkill, :rate_limited}
  ]

  # Start with 2 seconds for rate limits
  @rate_limit_initial_backoff 2000
  # Max 30 seconds for rate limits
  @rate_limit_max_backoff 30_000
  @default_max_retries 3
  # milliseconds
  @default_initial_backoff 500
  # milliseconds
  @default_max_backoff 5000
  # milliseconds (10 seconds)
  @default_timeout 10_000

  defmodule RequestContext do
    @moduledoc """
    Struct to hold request context information to reduce parameter count in functions.
    """
    defstruct [:method_str, :url, :headers, :body, :config, :retry_count]
  end

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
    AppLogger.api_debug("[DEBUG HTTP] Starting GET request to: #{url}")

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

    # Log the final URL that will be used
    AppLogger.api_debug("[DEBUG HTTP] Final URL after query params: #{url_with_query}")

    # Always enable rate limit awareness for GET requests
    opts = Keyword.put_new(opts, :rate_limit_aware, true)

    # Set higher default max retries for GET
    opts =
      if Keyword.has_key?(opts, :max_retries) do
        opts
      else
        Keyword.put(opts, :max_retries, 5)
      end

    AppLogger.api_debug("[DEBUG HTTP] Calling request() with URL: #{url_with_query}")
    result = request("GET", url_with_query, headers, "", opts)

    AppLogger.api_debug(
      "[DEBUG HTTP] GET request completed with result: #{inspect(result, limit: 200)}"
    )

    result
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
    rate_limit_aware = Keyword.get(opts, :rate_limit_aware, false)

    # Log the request at debug level
    if Keyword.get(opts, :debug, false) do
      log_request_debug(method, url, headers, body)
    end

    # Create request config to reduce arity
    request_config = %{
      max_retries: max_retries,
      initial_backoff: initial_backoff,
      timeout: timeout,
      label: label,
      rate_limit_aware: rate_limit_aware
    }

    # Start the request in a separate task
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

    try do
      # Wait for the result with timeout
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
  defp do_request_with_retry(method, url, headers, body, config, retry_count) do
    if retry_count > 10 do
      AppLogger.api_error("Exceeded maximum retry safety limit (10) for #{method} #{url}")
      return_server_error("Too many retries")
    end

    options = build_request_options(config)
    method_str = to_string(method) |> String.upcase()
    log_request_attempt(method_str, url, retry_count)

    case make_request(method, url, body, headers, options) do
      {:ok, response = %{status_code: status}} when status >= 200 and status < 300 ->
        handle_successful_response(response, method_str, config, status)

      {:ok, response = %{status_code: 429}} ->
        handle_rate_limit(method_str, url, headers, body, config, retry_count, response)

      {:ok, %{status_code: status}} when status >= 500 and status < 600 ->
        handle_server_error(method_str, url, headers, body, config, retry_count, status)

      {:ok, response = %{status_code: status, body: resp_body}} ->
        handle_other_response(
          %RequestContext{
            method_str: method_str,
            url: url,
            headers: headers,
            body: body,
            config: config,
            retry_count: retry_count
          },
          response,
          status,
          resp_body
        )

      {:error, %HTTPoison.Error{reason: reason}} ->
        handle_network_error(method_str, url, headers, body, config, retry_count, reason)
    end
  end

  defp build_request_options(config) do
    [
      hackney: [
        follow_redirect: true,
        recv_timeout: config.timeout,
        connect_timeout: div(config.timeout, 2)
      ]
    ]
  end

  defp log_request_attempt(method_str, url, retry_count) do
    AppLogger.api_debug(
      "[DEBUG HTTP] About to call HTTPoison.request: #{method_str} #{url}, retry #{retry_count}"
    )
  end

  defp make_request(method, url, body, headers, options) do
    # Add special logging for ESI requests
    if String.contains?(url, "esi.evetech.net") do
      kill_id = extract_kill_id_from_url(url)

      AppLogger.kill_info("📡 Making ESI HTTP request", %{
        method: method,
        url: url,
        kill_id: kill_id,
        headers: headers
      })

      start_time = System.monotonic_time(:millisecond)

      result = HTTPoison.request(method, url, body, headers, options)

      end_time = System.monotonic_time(:millisecond)
      duration_ms = end_time - start_time

      # Log the result
      case result do
        {:ok, response} ->
          AppLogger.kill_debug("📥 ESI HTTP response received", %{
            method: method,
            status: response.status_code,
            kill_id: kill_id,
            duration_ms: duration_ms,
            size: byte_size(response.body)
          })

        {:error, error} ->
          AppLogger.kill_info("❌ ESI HTTP error", %{
            method: method,
            kill_id: kill_id,
            error: inspect(error.reason),
            duration_ms: duration_ms
          })
      end

      result
    else
      # Regular non-ESI request
      HTTPoison.request(method, url, body, headers, options)
    end
  end

  # Helper to extract kill_id from URL for better logging
  defp extract_kill_id_from_url(url) do
    if String.contains?(url, "/killmails/") do
      case Regex.run(~r/\/killmails\/(\d+)\//, url) do
        [_, kill_id] -> kill_id
        _ -> nil
      end
    else
      nil
    end
  end

  defp handle_successful_response(response, method_str, config, status) do
    AppLogger.api_debug(
      "[DEBUG HTTP] Request successful: #{method_str} [#{config.label}] => status #{status}"
    )

    {:ok, response}
  end

  defp handle_rate_limit(method_str, url, headers, body, config, retry_count, response) do
    # Extract Retry-After header, if provided
    retry_after = extract_retry_after(response.headers) || 0

    # Check if this is an ESI domain call based on URL or config
    is_esi = String.contains?(url, "esi.evetech.net") || config.label == "ESI"

    # Calculate backoff - use much more aggressive values for ESI
    backoff_ms = if is_esi do
      # Base minimum time is 5 seconds (5000ms) plus random 1-10s additional jitter
      # Double each retry attempt
      base_backoff = max(5000 * :math.pow(2, retry_count), retry_after * 1000)
      jitter = 1000 + :rand.uniform(10000)

      # Cap at 60 seconds maximum to avoid very long waits
      trunc(min(base_backoff + jitter, 60000))
    else
      # For other APIs, use standard backoff calculation
      calculate_backoff(retry_count, retry_after * 1000, true)
    end

    # Log the rate limit with domain-specific information
    domain_info = if is_esi, do: " (ESI domain)", else: ""
    AppLogger.api_warn(
      "⚠️ RATE LIMIT (429) for #{method_str} #{url}#{domain_info} - waiting #{backoff_ms}ms before retry #{retry_count + 1}"
    )

    :timer.sleep(backoff_ms)
    do_request_with_retry(method_str, url, headers, body, config, retry_count + 1)
  end

  defp handle_server_error(method_str, url, headers, body, config, retry_count, status) do
    if retry_count < config.max_retries do
      backoff_ms = calculate_backoff(retry_count, 0, false)

      AppLogger.api_warn(
        "Server error (#{status}) for #{method_str} #{url} - retrying in #{backoff_ms}ms (#{retry_count + 1}/#{config.max_retries})"
      )

      :timer.sleep(backoff_ms)
      do_request_with_retry(method_str, url, headers, body, config, retry_count + 1)
    else
      AppLogger.api_error(
        "Server error (#{status}) persisted after #{config.max_retries} retries for #{method_str} #{url}"
      )

      {:error, :server_error}
    end
  end

  defp handle_other_response(
         %RequestContext{
           method_str: method_str,
           url: url,
           headers: _headers,
           body: _body,
           config: _config,
           retry_count: _retry_count
         } = context,
         response,
         status,
         resp_body
       ) do
    case check_for_domain_rate_limit(resp_body) do
      {:rate_limited, reason} ->
        handle_domain_rate_limit(context, reason)

      :no_rate_limit ->
        handle_non_rate_limited_response(method_str, url, response, status)
    end
  end

  defp handle_domain_rate_limit(%RequestContext{} = context, reason) do
    backoff_ms = calculate_backoff(context.retry_count, 0, true)

    AppLogger.api_warn(
      "Domain rate limit detected for #{context.method_str} #{context.url} (#{reason}) - waiting #{backoff_ms}ms before retry #{context.retry_count + 1}"
    )

    :timer.sleep(backoff_ms)

    do_request_with_retry(
      context.method_str,
      context.url,
      context.headers,
      context.body,
      context.config,
      context.retry_count + 1
    )
  end

  defp handle_non_rate_limited_response(method_str, url, response, status) do
    cond do
      status == 429 ->
        AppLogger.api_warn(
          "⚠️ Found 429 status that wasn't pattern-matched earlier - treating as rate limited"
        )

        {:error, :rate_limited}

      status >= 400 and status < 500 ->
        AppLogger.api_debug("[DEBUG HTTP] Client error (#{status}) for #{method_str} #{url}")
        {:error, status_code_to_error(status)}

      true ->
        AppLogger.api_debug("[DEBUG HTTP] Unexpected status (#{status}) for #{method_str} #{url}")
        {:ok, response}
    end
  end

  defp handle_network_error(method_str, url, headers, body, config, retry_count, reason) do
    if retry_count < config.max_retries and transient_error?(reason) do
      backoff_ms = calculate_backoff(retry_count, 0, false)

      AppLogger.api_warn(
        "Network error (#{inspect(reason)}) for #{method_str} #{url} - retrying in #{backoff_ms}ms (#{retry_count + 1}/#{config.max_retries})"
      )

      :timer.sleep(backoff_ms)
      do_request_with_retry(method_str, url, headers, body, config, retry_count + 1)
    else
      log_network_error_final(method_str, url, config.max_retries, retry_count, reason)
      {:error, reason}
    end
  end

  defp log_network_error_final(method_str, url, max_retries, retry_count, reason) do
    if retry_count >= max_retries do
      AppLogger.api_error(
        "Network error persisted after #{max_retries} retries for #{method_str} #{url}: #{inspect(reason)}"
      )
    else
      AppLogger.api_error(
        "Non-retryable network error for #{method_str} #{url}: #{inspect(reason)}"
      )
    end
  end

  # Calculate backoff time with exponential increase and jitter
  defp calculate_backoff(retry_count, retry_after_ms, is_rate_limit) do
    # For rate limits, use more aggressive backoff parameters
    {initial_ms, max_ms} =
      if is_rate_limit do
        {@rate_limit_initial_backoff, @rate_limit_max_backoff}
      else
        {@default_initial_backoff, @default_max_backoff}
      end

    # If retry_after is specified and larger than our calculated backoff, use it
    base_ms = max(initial_ms * :math.pow(2, retry_count), retry_after_ms)

    # Apply maximum
    capped_ms = min(base_ms, max_ms)

    # Add jitter (±20%)
    jitter = :rand.uniform(trunc(capped_ms * 0.4)) - trunc(capped_ms * 0.2)
    trunc(capped_ms + jitter)
  end

  # Check a response body for domain-specific rate limit indicators
  defp check_for_domain_rate_limit(body) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, decoded} when is_map(decoded) ->
        cond do
          # Check for explicit rate limit messages
          has_rate_limit_message?(decoded) ->
            {:rate_limited, extract_rate_limit_reason(decoded)}

          # Check for map domain-specific rate limits
          map_domain_rate_limited?(decoded) ->
            {:rate_limited, "map domain rate limit"}

          # No rate limit indicators found
          true ->
            :no_rate_limit
        end

      _ ->
        # Couldn't parse as JSON or not a map
        :no_rate_limit
    end
  end

  defp check_for_domain_rate_limit(_), do: :no_rate_limit

  # Check if a decoded JSON response contains rate limit messages
  defp has_rate_limit_message?(decoded) when is_map(decoded) do
    # Check error field
    # Check message field
    (Map.has_key?(decoded, "error") and
       is_binary(decoded["error"]) and
       String.contains?(String.downcase(decoded["error"]), "rate") and
       String.contains?(String.downcase(decoded["error"]), "limit")) or
      (Map.has_key?(decoded, "message") and
         is_binary(decoded["message"]) and
         String.contains?(String.downcase(decoded["message"]), "rate") and
         String.contains?(String.downcase(decoded["message"]), "limit"))
  end

  # Check for map domain-specific rate limits
  defp map_domain_rate_limited?(decoded) when is_map(decoded) do
    Map.has_key?(decoded, "domain") and
      decoded["domain"] == "map" and
      Map.has_key?(decoded, "error") and
      is_binary(decoded["error"]) and
      String.contains?(String.downcase(decoded["error"]), "rate")
  end

  # Extract a rate limit reason message from the decoded JSON
  defp extract_rate_limit_reason(decoded) when is_map(decoded) do
    cond do
      Map.has_key?(decoded, "error") and is_binary(decoded["error"]) ->
        decoded["error"]

      Map.has_key?(decoded, "message") and is_binary(decoded["message"]) ->
        decoded["message"]

      true ->
        "unknown rate limit reason"
    end
  end

  # Helper to convert status codes to error atoms
  defp status_code_to_error(status_code) do
    case status_code do
      400 -> :bad_request
      401 -> :unauthorized
      403 -> :forbidden
      404 -> :not_found
      409 -> :conflict
      # Should be handled separately above
      429 -> :rate_limited
      _ -> {:http_error, status_code}
    end
  end

  # Helper to return a generic server error
  defp return_server_error(reason) do
    {:error, {:server_error, reason}}
  end

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

    AppLogger.api_debug("""
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
  This is a convenience wrapper around ResponseHandler.

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

  def handle_response({:ok, %{status_code: 429}}, _decode_json) do
    # Special handling for rate limiting - this must come first!
    AppLogger.api_warn("Rate limit (429) received in handle_response")
    # Return specific rate limit error (will be retried by do_request_with_retry)
    {:error, :rate_limited}
  end

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
      ResponseHandler.handle_response(response, curl_example)
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

  # Determine if an error is transient and can be retried
  defp transient_error?(reason) do
    cond do
      is_atom(reason) -> reason in @transient_errors
      match?(%HTTPoison.Error{}, reason) -> httpoison_error_transient?(reason)
      is_tuple(reason) and tuple_size(reason) == 3 -> domain_error_transient?(reason)
      true -> false
    end
  end

  defp httpoison_error_transient?(%HTTPoison.Error{} = reason) do
    error_reason = reason.reason
    error_reason in @transient_errors or connection_error?(reason) or timeout_error?(reason)
  end

  defp domain_error_transient?(error_tuple) when elem(error_tuple, 0) == :domain_error do
    _domain = elem(error_tuple, 1)
    error_type = elem(error_tuple, 2)

    error_type == :rate_limited or error_tuple in @transient_errors
  end

  defp domain_error_transient?(_), do: false

  defp connection_error?(reason) do
    case reason do
      %HTTPoison.Error{reason: :closed} -> true
      %HTTPoison.Error{reason: :connect_timeout} -> true
      %HTTPoison.Error{reason: :econnrefused} -> true
      %HTTPoison.Error{reason: :enetdown} -> true
      %HTTPoison.Error{reason: :enetunreach} -> true
      %HTTPoison.Error{reason: :enotconn} -> true
      %HTTPoison.Error{reason: :econnreset} -> true
      _ -> false
    end
  end

  defp timeout_error?(reason) do
    case reason do
      %HTTPoison.Error{reason: :timeout} -> true
      %HTTPoison.Error{reason: :etimedout} -> true
      %HTTPoison.Error{reason: :ehostunreach} -> true
      _ -> false
    end
  end

  # Extract Retry-After header value, if present
  defp extract_retry_after(headers) do
    retry_header =
      Enum.find(headers, fn {header_name, _} ->
        String.downcase(header_name) == "retry-after"
      end)

    case retry_header do
      {_, value} ->
        # Try to parse as integer seconds
        case Integer.parse(value) do
          {seconds, _} -> seconds
          :error -> nil
        end

      nil ->
        nil
    end
  end
end
