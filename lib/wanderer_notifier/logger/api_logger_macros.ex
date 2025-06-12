defmodule WandererNotifier.Logger.ApiLoggerMacros do
  @moduledoc """
  Provides macros for common API logging patterns across the application.

  These macros standardize logging for HTTP requests, responses, caching operations,
  and error handling, ensuring consistent log formats and metadata structures.

  ## Usage

      use WandererNotifier.Logger.ApiLoggerMacros
      
      # In your module
      log_api_request(:get, url, "ESI")
      log_api_success(url, 200, duration_ms)
      log_api_error(url, {:http_error, 404}, duration_ms)
  """

  alias WandererNotifier.Logger.Logger, as: AppLogger

  defmacro __using__(_opts) do
    quote do
      import WandererNotifier.Logger.ApiLoggerMacros
      alias WandererNotifier.Utils.TimeUtils
    end
  end

  @doc """
  Logs the start of an API request.

  ## Parameters
    - method: HTTP method atom (:get, :post, etc.)
    - url: The URL being requested
    - client_name: Name of the client making the request
    - extra_metadata: Additional metadata to include

  ## Examples

      log_api_request(:get, "https://esi.evetech.net/v1/character/123", "ESI")
      log_api_request(:post, url, "ZKill", %{queue_id: queue_id})
  """
  defmacro log_api_request(method, url, client_name, extra_metadata \\ quote(do: %{})) do
    quote do
      AppLogger.api_debug(
        "API request starting",
        Map.merge(unquote(extra_metadata), %{
          method: unquote(method),
          url: unquote(url),
          client: unquote(client_name)
        })
      )
    end
  end

  @doc """
  Logs a successful API response.

  ## Parameters
    - url: The URL that was requested
    - status_code: HTTP status code
    - duration_ms: Request duration in milliseconds
    - extra_metadata: Additional metadata to include

  ## Examples

      log_api_success(url, 200, duration_ms)
      log_api_success(url, 201, duration_ms, %{response_size: byte_size(body)})
  """
  defmacro log_api_success(url, status_code, duration_ms, extra_metadata \\ quote(do: %{})) do
    quote do
      AppLogger.api_debug(
        "API request successful",
        Map.merge(unquote(extra_metadata), %{
          url: unquote(url),
          status_code: unquote(status_code),
          duration_ms: unquote(duration_ms)
        })
      )
    end
  end

  @doc """
  Logs an API error response.

  ## Parameters
    - url: The URL that was requested
    - error: The error (can be status code, tuple, or any term)
    - duration_ms: Request duration in milliseconds (optional)
    - extra_metadata: Additional metadata to include

  ## Examples

      log_api_error(url, {:http_error, 404}, duration_ms)
      log_api_error(url, :timeout)
      log_api_error(url, exception, duration_ms, %{retry_count: 3})
  """
  defmacro log_api_error(url, error, duration_ms \\ nil, extra_metadata \\ quote(do: %{})) do
    quote do
      metadata =
        unquote(extra_metadata)
        |> Map.put(:url, unquote(url))
        |> Map.put(:error, inspect(unquote(error)))

      metadata =
        if unquote(duration_ms) != nil do
          Map.put(metadata, :duration_ms, unquote(duration_ms))
        else
          metadata
        end

      # Add specific error details based on error type
      metadata =
        case unquote(error) do
          {:http_error, status} -> Map.put(metadata, :status_code, status)
          {:http_error, status, _body} -> Map.put(metadata, :status_code, status)
          :timeout -> Map.put(metadata, :error_type, :timeout)
          :connect_timeout -> Map.put(metadata, :error_type, :connect_timeout)
          _ -> metadata
        end

      AppLogger.api_error("API request failed", metadata)
    end
  end

  @doc """
  Logs a cache hit.

  ## Parameters
    - cache_key: The cache key that was hit
    - resource_type: Type of resource (e.g., "character", "system")
    - extra_metadata: Additional metadata to include

  ## Examples

      log_cache_hit("esi:character:123", "character")
      log_cache_hit(cache_key, "system", %{ttl: 3600})
  """
  defmacro log_cache_hit(cache_key, resource_type, extra_metadata \\ quote(do: %{})) do
    quote do
      AppLogger.api_debug(
        "Cache hit for #{unquote(resource_type)}",
        Map.merge(unquote(extra_metadata), %{
          cache_key: unquote(cache_key),
          resource_type: unquote(resource_type),
          operation: :get
        })
      )
    end
  end

  @doc """
  Logs a cache miss.

  ## Parameters
    - cache_key: The cache key that missed
    - resource_type: Type of resource
    - extra_metadata: Additional metadata to include

  ## Examples

      log_cache_miss("esi:character:123", "character")
  """
  defmacro log_cache_miss(cache_key, resource_type, extra_metadata \\ quote(do: %{})) do
    quote do
      AppLogger.api_debug(
        "Cache miss for #{unquote(resource_type)}, fetching from API",
        Map.merge(unquote(extra_metadata), %{
          cache_key: unquote(cache_key),
          resource_type: unquote(resource_type),
          operation: :get
        })
      )
    end
  end

  @doc """
  Logs a client-specific message with standard formatting.

  ## Parameters
    - level: Log level (:debug, :info, :warn, :error)
    - client_name: Name of the client (e.g., "ESI", "ZKill")
    - message: The log message
    - metadata: Metadata map

  ## Examples

      log_client_message(:error, "ESI", "Character not found", %{character_id: 123})
      log_client_message(:info, "License", "Validation successful", %{valid: true})
  """
  defmacro log_client_message(level, client_name, message, metadata \\ quote(do: %{})) do
    quote do
      full_message = "#{unquote(client_name)} Client: #{unquote(message)}"
      metadata = Map.put(unquote(metadata), :client, unquote(client_name))

      case unquote(level) do
        :debug -> AppLogger.api_debug(full_message, metadata)
        :info -> AppLogger.api_info(full_message, metadata)
        :warn -> AppLogger.api_warn(full_message, metadata)
        :error -> AppLogger.api_error(full_message, metadata)
      end
    end
  end

  @doc """
  Logs a timeout with appropriate context.

  ## Parameters
    - timeout_type: Type of timeout (:timeout, :connect_timeout, :recv_timeout)
    - url: The URL that timed out
    - client_name: Name of the client
    - extra_metadata: Additional metadata

  ## Examples

      log_timeout(:connect_timeout, url, "ESI")
      log_timeout(:timeout, url, "RedisQ", %{queue_id: queue_id, consecutive: 5})
  """
  defmacro log_timeout(timeout_type, url, client_name, extra_metadata \\ quote(do: %{})) do
    quote do
      message =
        case unquote(timeout_type) do
          :connect_timeout -> "Connection timeout"
          :recv_timeout -> "Receive timeout"
          _ -> "Request timeout"
        end

      AppLogger.api_error(
        "#{unquote(client_name)} Client: #{message}",
        Map.merge(unquote(extra_metadata), %{
          url: unquote(url),
          client: unquote(client_name),
          timeout_type: unquote(timeout_type)
        })
      )
    end
  end

  @doc """
  Wraps a function call with timing and logs the result.

  ## Parameters
    - do_block: The code block to time and execute
    - url: The URL being called
    - client_name: Name of the client
    - extra_metadata: Additional metadata

  ## Examples

      with_api_timing url, "ESI" do
        HTTP.get(url, headers, opts)
      end

  This will automatically log the request start, measure duration, and log success/error.
  """
  defmacro with_api_timing(url, client_name, extra_metadata \\ quote(do: %{}), do: do_block) do
    quote do
      start_time = TimeUtils.monotonic_ms()
      log_api_request(:get, unquote(url), unquote(client_name), unquote(extra_metadata))

      result = unquote(do_block)

      duration_ms = TimeUtils.monotonic_ms() - start_time
      log_and_return_result(result, unquote(url), duration_ms, unquote(extra_metadata))
    end
  end

  @doc false
  defmacro log_and_return_result(result, url, duration_ms, extra_metadata) do
    quote do
      case unquote(result) do
        {:ok, %{status_code: status} = response} ->
          if status in 200..299 do
            log_api_success(unquote(url), status, unquote(duration_ms), unquote(extra_metadata))
            {:ok, response}
          else
            log_api_error(
              unquote(url),
              {:http_error, status},
              unquote(duration_ms),
              unquote(extra_metadata)
            )

            unquote(result)
          end

        {:error, reason} ->
          log_api_error(unquote(url), reason, unquote(duration_ms), unquote(extra_metadata))
          unquote(result)

        other ->
          other
      end
    end
  end

  @doc """
  Creates a standardized log context map for API operations.

  ## Parameters
    - client_name: Name of the client
    - resource_type: Type of resource being accessed
    - resource_id: ID of the resource
    - extra: Additional context fields

  ## Examples

      context = api_log_context("ESI", "character", character_id)
      context = api_log_context("ZKill", "killmail", kill_id, %{hash: hash})
  """
  defmacro api_log_context(client_name, resource_type, resource_id, extra \\ quote(do: %{})) do
    quote do
      Map.merge(unquote(extra), %{
        client: unquote(client_name),
        resource_type: unquote(resource_type),
        "#{unquote(resource_type)}_id": unquote(resource_id)
      })
    end
  end
end
