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
    case error do
      # Transient errors that can be retried
      :timeout ->
        :transient

      :connection_error ->
        :transient

      :server_error ->
        :transient

      :rate_limited ->
        :transient

      {:econnrefused, _} ->
        :transient

      {:closed, _} ->
        :transient

      {:timeout, _} ->
        :transient

      :econnrefused ->
        :transient

      :enetunreach ->
        :transient

      :system_limit ->
        :transient

      # Permanent errors that cannot be retried
      :not_found ->
        :permanent

      :unauthorized ->
        :permanent

      :forbidden ->
        :permanent

      :bad_request ->
        :permanent

      :json_error ->
        :permanent

      :unsupported_media_type ->
        :permanent

      :conflict ->
        :permanent

      :client_error ->
        :permanent

      # Domain-specific errors may be either
      {:domain_error, domain, reason} ->
        classify_domain_error(domain, reason)

      # All other errors are assumed permanent by default
      _ ->
        :permanent
    end
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

    case response do
      # Handle raw response map directly (most common case)
      %{status_code: status, body: body} when status in 200..299 ->
        # Handle JSON string properly, whether it's already parsed or not
        cond do
          # If it's a binary (string) and we want to decode JSON
          decode_json and is_binary(body) and body != "" ->
            case Jason.decode(body) do
              {:ok, data} ->
                {:ok, data}

              {:error, reason} ->
                log(log_level, "#{tag} JSON decode error: #{inspect(reason)}")
                {:error, :json_error}
            end

          # If we already have a map or other data structure and don't need JSON decoding
          true ->
            {:ok, body}
        end

      # Handle tuple response with :ok atom
      {:ok, %{status_code: status, body: body}} when status in 200..299 ->
        # Handle JSON string properly, whether it's already parsed or not
        cond do
          # If it's a binary (string) and we want to decode JSON
          decode_json and is_binary(body) and body != "" ->
            case Jason.decode(body) do
              {:ok, data} ->
                {:ok, data}

              {:error, reason} ->
                log(log_level, "#{tag} JSON decode error: #{inspect(reason)}")
                {:error, :json_error}
            end

          # If we already have a map or other data structure and don't need JSON decoding
          true ->
            {:ok, body}
        end

      # Handle raw response map for non-success status
      %{status_code: status, body: body} ->
        error = status_to_error(status)
        domain_error = if domain, do: domain_specific_error(domain, status, body), else: error

        log(log_level, "#{tag} Request failed with status #{status}: #{inspect(error)}")
        if body != "", do: log(:debug, "#{tag} Response body: #{inspect(body)}")

        {:error, domain_error}

      # Handle tuple response for non-success status
      {:ok, %{status_code: status, body: body}} ->
        error = status_to_error(status)
        domain_error = if domain, do: domain_specific_error(domain, status, body), else: error

        log(log_level, "#{tag} Request failed with status #{status}: #{inspect(error)}")
        if body != "", do: log(:debug, "#{tag} Response body: #{inspect(body)}")

        {:error, domain_error}

      # Handle plain error tuple
      {:error, reason} ->
        handle_http_error(reason, opts)

      # Fallback for any other response format - this is essential
      other ->
        log(log_level, "#{tag} Unexpected response format: #{inspect(other)}")

        # Try to extract meaningful data if possible
        cond do
          is_map(other) and Map.has_key?(other, :body) and is_binary(other.body) ->
            # Try to parse body as JSON
            case Jason.decode(other.body) do
              {:ok, data} -> {:ok, data}
              _ -> {:ok, other.body}
            end

          is_binary(other) ->
            # Try to parse as JSON string
            case Jason.decode(other) do
              {:ok, data} -> {:ok, data}
              _ -> {:ok, other}
            end

          true ->
            {:error, {:unexpected_format, other}}
        end
    end
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

  @doc """
  Converts an HTTP status code to a standardized error type.

  ## Examples
      iex> ErrorHandler.status_to_error(404)
      :not_found

      iex> ErrorHandler.status_to_error(500)
      :server_error
  """
  @spec status_to_error(integer()) :: error_type() | {:unexpected_status, integer()}
  def status_to_error(status) do
    case status do
      400 -> :bad_request
      401 -> :unauthorized
      403 -> :forbidden
      404 -> :not_found
      409 -> :conflict
      415 -> :unsupported_media_type
      429 -> :rate_limited
      code when code in 400..499 -> :client_error
      code when code in 500..599 -> :server_error
      _ -> {:unexpected_status, status}
    end
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
    case reason do
      :timeout -> :timeout
      {:timeout, _} -> :timeout
      :econnrefused -> :connection_error
      {:econnrefused, _} -> :connection_error
      :closed -> :connection_error
      {:closed, _} -> :connection_error
      :enetunreach -> :connection_error
      :system_limit -> :connection_error
      error when error in @error_types -> error
      _ -> :connection_error
    end
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

  # Domain-specific error classification
  defp classify_domain_error(domain, reason) do
    case domain do
      :esi ->
        case reason do
          {:not_found, _} -> :permanent
          {:bad_request, _} -> :permanent
          {:server_error, _} -> :transient
          _ -> :permanent
        end

      :discord ->
        case reason do
          {:rate_limited, _} -> :transient
          {:server_error, _} -> :transient
          _ -> :permanent
        end

      _ ->
        :permanent
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

  # Discord-specific error handling
  defp handle_discord_error(status_or_error, body_or_reason) do
    error =
      if is_integer(status_or_error), do: status_to_error(status_or_error), else: status_or_error

    error_code = extract_discord_error_code(body_or_reason)

    case {error, error_code} do
      {:unauthorized, _} ->
        {:domain_error, :discord, {:unauthorized, :invalid_token}}

      {:forbidden, _} ->
        {:domain_error, :discord, {:forbidden, :missing_permissions}}

      {:rate_limited, _} ->
        {:domain_error, :discord, {:rate_limited, :discord_rate_limit}}

      {:bad_request, 50_006} ->
        {:domain_error, :discord, {:bad_request, :empty_message}}

      {:bad_request, _} ->
        {:domain_error, :discord, {:bad_request, error_code || :general}}

      _ ->
        {:domain_error, :discord, {error, error_code || :general}}
    end
  end

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
