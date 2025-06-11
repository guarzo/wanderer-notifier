defmodule WandererNotifier.Logger.ErrorLogger do
  @moduledoc """
  Provides consistent error logging patterns across the application.
  This module centralizes error logging to ensure consistent formatting and metadata.
  """

  alias WandererNotifier.Logger.Logger, as: AppLogger

  @doc """
  Logs an API error with consistent formatting.

  ## Parameters
    - message: The error message
    - metadata: Additional metadata to include in the log
  """
  def log_api_error(message, metadata \\ []) do
    AppLogger.api_error(message, metadata)
  end

  @doc """
  Logs a killmail processing error with consistent formatting.

  ## Parameters
    - message: The error message
    - metadata: Additional metadata to include in the log
  """
  def log_kill_error(message, metadata \\ []) do
    AppLogger.kill_error(message, metadata)
  end

  @doc """
  Logs a configuration error with consistent formatting.

  ## Parameters
    - message: The error message
    - metadata: Additional metadata to include in the log
  """
  def log_config_error(message, metadata \\ []) do
    AppLogger.config_error(message, metadata)
  end

  @doc """
  Logs a processor error with consistent formatting.

  ## Parameters
    - message: The error message
    - metadata: Additional metadata to include in the log
  """
  def log_processor_error(message, metadata \\ []) do
    AppLogger.processor_error(message, metadata)
  end

  @doc """
  Logs a notification error with consistent formatting.

  ## Parameters
    - message: The error message
    - metadata: Additional metadata to include in the log
  """
  def log_notification_error(message, metadata \\ []) do
    AppLogger.notification_error(message, metadata)
  end

  @doc """
  Logs an exception with its stacktrace.
  """
  def log_exception(message, exception, metadata \\ []) do
    try do
      AppLogger.error(
        message,
        Keyword.merge(metadata,
          error: Exception.message(exception),
          stacktrace:
            Exception.format_stacktrace(Process.info(self(), :current_stacktrace) |> elem(1))
        )
      )
    rescue
      _ ->
        # If we can't format the stacktrace, just log the error
        AppLogger.error(
          message,
          Keyword.merge(metadata,
            error: Exception.message(exception)
          )
        )
    end
  end

  @doc """
  Logs an HTTP request error with consistent formatting.

  ## Parameters
    - method: The HTTP method
    - url: The request URL
    - reason: The error reason
    - start_time: The request start time for duration calculation
    - metadata: Additional metadata to include in the log
  """
  def log_http_error(method, url, reason, start_time, metadata \\ []) do
    duration = System.monotonic_time() - start_time

    AppLogger.api_error(
      "HTTP request failed",
      Keyword.merge(metadata,
        method: method,
        url: url,
        error: inspect(reason),
        duration_ms: duration / 1_000_000
      )
    )
  end

  @doc """
  Logs a validation error with consistent formatting.

  ## Parameters
    - message: The error message
    - entity: The entity being validated
    - reason: The validation reason
    - metadata: Additional metadata to include in the log
  """
  def log_validation_error(message, entity, reason, metadata \\ []) do
    AppLogger.error(
      message,
      Keyword.merge(metadata,
        entity: inspect(entity),
        reason: inspect(reason)
      )
    )
  end

  @doc """
  Logs a cache error with consistent formatting.

  ## Parameters
    - message: The error message
    - key: The cache key
    - reason: The error reason
    - metadata: Additional metadata to include in the log
  """
  def log_cache_error(message, key, reason, metadata \\ []) do
    AppLogger.cache_error(
      message,
      Keyword.merge(metadata,
        key: key,
        error: inspect(reason)
      )
    )
  end
end
