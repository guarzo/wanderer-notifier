defmodule WandererNotifier.Api.Http.ErrorHandler do
  @moduledoc """
  Unified HTTP error handling module for consistent error handling across API clients.

  This module provides:
  1. Standardized error types for HTTP operations
  2. Error conversion from HTTP responses to domain-specific errors
  3. Consistent logging and formatting for errors
  4. Response transformation utilities

  Usage:
  ```elixir
  alias WandererNotifier.Api.Http.ErrorHandler

  # Handle generic HTTP response
  case HttpClient.get(url) do
    {:ok, response} -> ErrorHandler.handle_http_response(response)
    {:error, reason} -> ErrorHandler.handle_http_error(reason)
  end

  # Handle domain-specific errors
  case ErrorHandler.handle_http_response(response, domain: :esi) do
    {:ok, data} -> # Handle success
    {:error, error} ->
      case ErrorHandler.classify_error(error) do
        :transient -> # Can retry
        :permanent -> # Cannot retry
      end
  end
  ```
  """
  require Logger

  # Common error types that can be returned from HTTP operations:
  #
  # - :connection_error - Failed to connect to the server
  # - :timeout - Request timed out
  # - :server_error - Server returned 5xx status code
  # - :client_error - Client error (4xx other than specific ones below)
  # - :not_found - Resource not found (404)
  # - :unauthorized - Authentication failed (401)
  # - :forbidden - Authorization failed (403)
  # - :rate_limited - Too many requests (429)
  # - :bad_request - Invalid request (400)
  # - :json_error - Failed to parse JSON response
  # - :unsupported_media_type - Media type not supported (415)
  # - :conflict - Resource conflict (409)
  @error_types [
    :connection_error,
    :timeout,
    :server_error,
    :client_error,
    :not_found,
    :unauthorized,
    :forbidden,
    :rate_limited,
    :bad_request,
    :json_error,
    :unsupported_media_type,
    :conflict
  ]

  @type error_type ::
          :connection_error
          | :timeout
          | :server_error
          | :client_error
          | :not_found
          | :unauthorized
          | :forbidden
          | :rate_limited
          | :bad_request
          | :json_error
          | :unsupported_media_type
          | :conflict

  @type http_error ::
          error_type()
          | {:unexpected_status, integer()}
          | {:domain_error, atom(), any()}
          | any()

  @doc """
  Classifies errors as transient (can be retried) or permanent (cannot be retried).

  ## Examples
      iex> ErrorHandler.classify_error(:timeout)
      :transient

      iex> ErrorHandler.classify_error(:not_found)
      :permanent
  """
  @spec classify_error(http_error()) :: :transient | :permanent
  def classify_error(error) do
    cond do
      error in transient_errors() -> :transient
      error in permanent_errors() -> :permanent
      is_tuple(error) && elem(error, 0) in transient_tuple_errors() -> :transient
      # Default to permanent for unknown errors
      true -> :permanent
    end
  end

  # List of errors that are transient (can be retried)
  defp transient_errors do
    [
      :timeout,
      :connection_error,
      :server_error,
      :rate_limited,
      :econnrefused,
      :enetunreach,
      :system_limit,
      :connect_timeout,
      :checkout_timeout,
      :overload,
      :service_unavailable
    ]
  end

  # List of tuple errors where the first element indicates a transient error
  defp transient_tuple_errors do
    [
      :econnrefused,
      :closed,
      :timeout,
      :enetunreach,
      :server_error
    ]
  end

  # List of errors that are permanent (cannot be retried)
  defp permanent_errors do
    [
      :not_found,
      :unauthorized,
      :forbidden,
      :bad_request,
      :json_error,
      :unsupported_media_type,
      :client_error,
      :invalid_request,
      :not_implemented
    ]
  end

  @doc """
  Determines if an error is retryable based on its classification.

  ## Examples
      iex> ErrorHandler.retryable?(:timeout)
      true

      iex> ErrorHandler.retryable?(:not_found)
      false
  """
  @spec retryable?(http_error()) :: boolean()
  def retryable?(error), do: classify_error(error) == :transient

  @doc """
  Handles HTTP response by converting it to a consistent format.

  Options:
  - :decode_json - Whether to decode the response body as JSON (default: true)
  - :log_level - The log level for errors (default: :error)
  - :domain - The domain to use for domain-specific error handling (optional)
  - :tag - An optional tag to include in error logs for easier identification

  Returns:
  - {:ok, data} on success
  - {:error, error} on failure
  """
  @spec handle_http_response(
          {:ok, %{status_code: integer(), body: String.t(), headers: list()}}
          | %{status_code: integer(), body: String.t(), headers: list()},
          Keyword.t()
        ) :: {:ok, any()} | {:error, http_error()}
  def handle_http_response(response, opts \\ []) do
    decode_json = Keyword.get(opts, :decode_json, true)
    log_level = Keyword.get(opts, :log_level, :error)
    domain = Keyword.get(opts, :domain)
    tag = Keyword.get(opts, :tag, "HTTP")

    # Log the response type to help with debugging
    Logger.debug("#{tag} Response type: #{inspect(response)}")

    # Normalize response format to handle both direct maps and {:ok, map} tuples
    normalized_response = normalize_response(response)

    # Process based on status code
    case normalized_response do
      %{status_code: status, body: body} when status in 200..299 ->
        handle_success_response(body, decode_json, log_level, tag)

      %{status_code: status, body: body} ->
        handle_error_response(status, body, domain, log_level, tag)

      {:error, _} = error ->
        error
    end
  end

  # Normalize response to a consistent format
  defp normalize_response({:ok, response_map}), do: response_map
  defp normalize_response(response_map) when is_map(response_map), do: response_map
  defp normalize_response(error), do: error

  # Handle success responses (200-299 status codes)
  defp handle_success_response(body, decode_json, log_level, tag) do
    if decode_json and is_binary(body) and body != "" do
      case Jason.decode(body) do
        {:ok, data} ->
          {:ok, data}

        {:error, reason} ->
          log(log_level, "#{tag} JSON decode error: #{inspect(reason)}")
          {:error, :json_error}
      end
    else
      # If we already have a map or other data structure and don't need JSON decoding
      {:ok, body}
    end
  end

  # Handle error responses (non 200-299 status codes)
  defp handle_error_response(status, body, domain, log_level, tag) do
    error = status_to_error(status)
    domain_error = if domain, do: domain_specific_error(domain, status, body), else: error

    log(log_level, "#{tag} Request failed with status #{status}: #{inspect(error)}")
    if body != "", do: log(:debug, "#{tag} Response body: #{inspect(body)}")

    {:error, domain_error}
  end

  @doc """
  Handles HTTP errors consistently.

  Options:
  - :log_level - The log level for errors (default: :error)
  - :domain - The domain to use for domain-specific error handling (optional)
  - :tag - An optional tag to include in error logs for easier identification

  Returns:
  - {:error, error_type}
  """
  @spec handle_http_error(any(), Keyword.t()) :: {:error, http_error()}
  def handle_http_error(reason, opts \\ []) do
    log_level = Keyword.get(opts, :log_level, :error)
    domain = Keyword.get(opts, :domain)
    tag = Keyword.get(opts, :tag, "HTTP")

    error = error_to_type(reason)
    domain_error = if domain, do: domain_specific_error(domain, error, reason), else: error

    log(log_level, "#{tag} Request failed: #{inspect(reason)}")

    {:error, domain_error}
  end

  @client_errors %{
    400 => :bad_request,
    401 => :unauthorized,
    403 => :forbidden,
    404 => :not_found,
    409 => :conflict,
    415 => :unsupported_media_type,
    429 => :rate_limited
  }

  @spec status_to_error(integer()) :: error_type() | {:unexpected_status, integer()}
  def status_to_error(status) do
    cond do
      specific_error?(status) -> @client_errors[status]
      client_error?(status) -> :client_error
      server_error?(status) -> :server_error
      true -> {:unexpected_status, status}
    end
  end

  # Check if the status is a specific named error
  defp specific_error?(status) do
    Map.has_key?(@client_errors, status)
  end

  # Check if the status is in the 400-499 range (client error)
  defp client_error?(status) do
    status in 400..499
  end

  # Check if the status is in the 500-599 range (server error)
  defp server_error?(status) do
    status in 500..599
  end

  @doc """
  Converts various error reasons to standardized error types.

  ## Examples
      iex> ErrorHandler.error_to_type(:timeout)
      :timeout

      iex> ErrorHandler.error_to_type({:econnrefused, nil})
      :connection_error
  """
  @spec error_to_type(any()) :: error_type()
  def error_to_type(reason) do
    cond do
      timeout_error?(reason) -> :timeout
      connection_error?(reason) -> :connection_error
      known_error_type?(reason) -> reason
      true -> :connection_error
    end
  end

  # Check if the error is a timeout
  defp timeout_error?(reason) do
    reason == :timeout || match?({:timeout, _}, reason)
  end

  # Check if the error is a known connection error
  defp connection_error?(reason) do
    connection_errors = [
      :econnrefused,
      :closed,
      :enetunreach,
      :system_limit
    ]

    reason in connection_errors ||
      match?({:econnrefused, _}, reason) ||
      match?({:closed, _}, reason)
  end

  # Check if the error is a predefined error type
  defp known_error_type?(reason) do
    reason in @error_types
  end

  @doc """
  Annotates an error with additional context.

  ## Examples
      iex> ErrorHandler.annotate_error(:timeout, :esi_api, :get_killmail)
      {:domain_error, :esi_api, {:timeout, :get_killmail}}
  """
  @spec annotate_error(http_error(), atom(), any()) ::
          {:domain_error, atom(), {http_error(), any()}}
  def annotate_error(error, domain, context) do
    {:domain_error, domain, {error, context}}
  end

  @doc """
  Enriches data with additional information from the response headers.

  Options:
  - :extract - A list of header names to extract
  - :transform - A function to transform the data with the extracted headers

  ## Examples
      iex> ErrorHandler.enrich_with_headers({:ok, %{data: "example"}}, [{"X-Pages", "5"}], extract: ["X-Pages"], transform: fn data, headers -> Map.put(data, :pages, headers["X-Pages"]) end)
      {:ok, %{data: "example", pages: "5"}}
  """
  @spec enrich_with_headers({:ok, map()}, list(), Keyword.t()) :: {:ok, map()}
  def enrich_with_headers({:ok, data}, headers, opts) do
    extract = Keyword.get(opts, :extract, [])
    transform = Keyword.get(opts, :transform)

    # Convert headers to a map for easier access
    header_map = headers_to_map(headers, extract)

    # Transform the data if a transform function is provided
    if transform && is_function(transform, 2) do
      {:ok, transform.(data, header_map)}
    else
      # Default transformation just merges headers into the data
      {:ok, Map.merge(data, %{headers: header_map})}
    end
  end

  def enrich_with_headers(error, _headers, _opts), do: error

  # Converts a list of headers to a map, filtering by the list of keys to extract
  defp headers_to_map(headers, extract) do
    headers
    |> Enum.filter(fn {key, _} ->
      normalized_key = normalize_header_key(key)
      extract == [] or normalized_key in extract
    end)
    |> Enum.map(fn {key, value} -> {normalize_header_key(key), value} end)
    |> Enum.into(%{})
  end

  # Normalizes header keys to a consistent format
  defp normalize_header_key(key) do
    key
    |> to_string()
    |> String.downcase()
    |> String.replace("-", "_")
  end

  # Domain-specific error handling, extensible for different API domains
  defp domain_specific_error(domain, status_or_error, body_or_reason) do
    case domain do
      :esi -> handle_esi_error(status_or_error, body_or_reason)
      :zkill -> handle_zkill_error(status_or_error, body_or_reason)
      :discord -> handle_discord_error(status_or_error, body_or_reason)
      :map -> handle_map_error(status_or_error, body_or_reason)
      _ -> status_or_error
    end
  end

  # ESI-specific error handling
  defp handle_esi_error(status_or_error, body_or_reason) do
    error =
      if is_integer(status_or_error), do: status_to_error(status_or_error), else: status_or_error

    case {error, body_or_reason} do
      {:not_found, _} ->
        {:domain_error, :esi, {:not_found, :resource_not_found}}

      {:server_error, _} when is_binary(body_or_reason) ->
        if String.contains?(body_or_reason, "database timeout") do
          {:domain_error, :esi, {:server_error, :database_timeout}}
        else
          {:domain_error, :esi, {:server_error, :general}}
        end

      {:rate_limited, _} ->
        {:domain_error, :esi, {:rate_limited, :esi_rate_limit}}

      _ ->
        {:domain_error, :esi, {error, :general}}
    end
  end

  # zKill-specific error handling
  defp handle_zkill_error(status_or_error, body_or_reason) do
    error =
      if is_integer(status_or_error), do: status_to_error(status_or_error), else: status_or_error

    case {error, body_or_reason} do
      {:not_found, _} ->
        {:domain_error, :zkill, {:not_found, :killmail_not_found}}

      {:server_error, _} ->
        {:domain_error, :zkill, {:server_error, :zkill_api_error}}

      _ ->
        {:domain_error, :zkill, {error, :general}}
    end
  end

  # Discord-specific error handling - main function
  defp handle_discord_error(status_or_error, body_or_reason) do
    # Convert HTTP status to error atom if needed
    error = normalize_error(status_or_error)

    # Extract Discord's error code
    error_code = extract_discord_error_code(body_or_reason)

    # Process the specific error
    create_discord_error(error, error_code)
  end

  # Normalize error by converting status to error atom if needed
  defp normalize_error(status_or_error) when is_integer(status_or_error),
    do: status_to_error(status_or_error)

  defp normalize_error(error), do: error

  # Pattern match on specific Discord error types
  defp create_discord_error(:unauthorized, _),
    do: {:domain_error, :discord, {:unauthorized, :invalid_token}}

  defp create_discord_error(:forbidden, _),
    do: {:domain_error, :discord, {:forbidden, :missing_permissions}}

  defp create_discord_error(:rate_limited, _),
    do: {:domain_error, :discord, {:rate_limited, :discord_rate_limit}}

  defp create_discord_error(:bad_request, 50_006),
    do: {:domain_error, :discord, {:bad_request, :empty_message}}

  defp create_discord_error(:bad_request, error_code),
    do: {:domain_error, :discord, {:bad_request, error_code || :general}}

  # Fallback for all other error types
  defp create_discord_error(error, error_code),
    do: {:domain_error, :discord, {error, error_code || :general}}

  # Map API-specific error handling
  defp handle_map_error(status_or_error, body_or_reason) do
    error =
      if is_integer(status_or_error), do: status_to_error(status_or_error), else: status_or_error

    case {error, body_or_reason} do
      {:not_found, _} ->
        {:domain_error, :map, {:not_found, :resource_not_found}}

      {:server_error, _} ->
        {:domain_error, :map, {:server_error, :map_api_error}}

      _ ->
        {:domain_error, :map, {error, :general}}
    end
  end

  # Helper to extract Discord error codes
  defp extract_discord_error_code(body) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, %{"code" => code}} when is_integer(code) -> code
      _ -> nil
    end
  end

  defp extract_discord_error_code(_), do: nil

  # Helper for consistent logging
  defp log(level, message) do
    case level do
      :debug -> Logger.debug(message)
      :info -> Logger.info(message)
      :warning -> Logger.warning(message)
      :error -> Logger.error(message)
      _ -> Logger.debug(message)
    end
  end
end
