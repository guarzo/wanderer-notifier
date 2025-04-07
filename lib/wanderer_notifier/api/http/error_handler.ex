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

  ## Common error types

  - `:connection_error` - Failed to connect to the server
  - `:timeout` - Request timed out
  - `:server_error` - Server returned 5xx status code
  - `:client_error` - Client error (4xx other than specific ones below)
  - `:not_found` - Resource not found (404)
  - `:unauthorized` - Authentication failed (401)
  - `:forbidden` - Authorization failed (403)
  - `:rate_limited` - Too many requests (429)
  - `:bad_request` - Invalid request (400)
  - `:json_error` - Failed to parse JSON response
  - `:unsupported_media_type` - Media type not supported (415)
  - `:conflict` - Resource conflict (409)
  """
  alias WandererNotifier.Logger.Logger, as: AppLogger

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
      :service_unavailable,
      {:domain_error, :map, :rate_limited}
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
    AppLogger.api_debug("Processing response", tag: tag, response_type: inspect(response))

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
          log_http_error(log_level, "JSON decode error", tag: tag, error: inspect(reason))
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

    log_http_error(log_level, "Request failed",
      tag: tag,
      status: status,
      error: inspect(error)
    )

    if body != "" do
      AppLogger.api_debug("Response body", tag: tag, body: inspect(body))
    end

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
    domain_error = if domain, do: domain_specific_error(domain, nil, nil, error), else: error

    log_http_error(log_level, "Request error",
      tag: tag,
      error_type: inspect(error),
      reason: inspect(reason)
    )

    {:error, domain_error}
  end

  # Helper functions to convert error reasons to standard error types
  defp error_to_type(:econnrefused), do: :connection_error
  defp error_to_type(:enetunreach), do: :connection_error
  defp error_to_type(:timeout), do: :timeout
  defp error_to_type(:connect_timeout), do: :timeout
  defp error_to_type(:checkout_timeout), do: :timeout
  defp error_to_type({:closed, _}), do: :connection_error
  defp error_to_type({:timeout, _}), do: :timeout
  defp error_to_type({:timeout, _, _}), do: :timeout
  defp error_to_type(error) when is_atom(error), do: error
  defp error_to_type(_), do: :connection_error

  # Convert HTTP status codes to standard error types
  defp status_to_error(400), do: :bad_request
  defp status_to_error(401), do: :unauthorized
  defp status_to_error(403), do: :forbidden
  defp status_to_error(404), do: :not_found
  defp status_to_error(409), do: :conflict
  defp status_to_error(415), do: :unsupported_media_type
  defp status_to_error(429), do: :rate_limited
  defp status_to_error(status) when status >= 500 and status < 600, do: :server_error
  defp status_to_error(status) when status >= 400 and status < 500, do: :client_error
  defp status_to_error(status), do: {:unexpected_status, status}

  # Domain-specific error handling with enriched information
  defp domain_specific_error(domain, status, body, error_type \\ nil)

  defp domain_specific_error(:esi, status, body, error_type) do
    error_from_body = extract_esi_error(body)
    error_from_status = error_type || status_to_error(status)

    case error_from_body do
      nil -> error_from_status
      error -> {:domain_error, :esi, error}
    end
  end

  defp domain_specific_error(:zkill, status, _body, error_type) do
    error_from_status = error_type || status_to_error(status)
    {:domain_error, :zkill, error_from_status}
  end

  defp domain_specific_error(:map, status, _body, error_type) do
    error_from_status = error_type || status_to_error(status)
    {:domain_error, :map, error_from_status}
  end

  defp domain_specific_error(:discord, status, body, error_type) do
    # Extract Discord error code and message if available
    discord_error = extract_discord_error(body)
    error_from_status = error_type || status_to_error(status)

    case discord_error do
      nil -> {:domain_error, :discord, error_from_status}
      error -> {:domain_error, :discord, error}
    end
  end

  defp domain_specific_error(domain, status, _body, error_type) do
    error_from_status = error_type || status_to_error(status)
    {:domain_error, domain, error_from_status}
  end

  # Extract error information from ESI response body
  defp extract_esi_error(nil), do: nil

  defp extract_esi_error(body) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, %{"error" => error}} -> error
      _ -> nil
    end
  end

  defp extract_esi_error(_), do: nil

  # Extract error information from Discord API response
  defp extract_discord_error(nil), do: nil

  defp extract_discord_error(body) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, %{"code" => code, "message" => message}} ->
        %{code: code, message: message}

      {:ok, %{"message" => message}} ->
        %{message: message}

      _ ->
        nil
    end
  end

  defp extract_discord_error(_), do: nil

  # Helper function for structured logging at different levels
  defp log_http_error(level, message, metadata) when level in [:debug, :info, :warn, :error] do
    case level do
      :debug -> AppLogger.api_debug(message, metadata)
      :info -> AppLogger.api_info(message, metadata)
      :warn -> AppLogger.api_warn(message, metadata)
      :error -> AppLogger.api_error(message, metadata)
    end
  end
end
