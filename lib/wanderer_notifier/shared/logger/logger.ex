defmodule WandererNotifier.Shared.Logger.Logger do
  @moduledoc """
  Core logging module for WandererNotifier.

  This module provides the central logging API with delegations to specialized modules:
  - `CategoryLogger` - Category-specific logging functions
  - `MetadataProcessor` - Metadata normalization and processing
  - `BatchLogger` - Batch logging for high-volume events  
  - `StartupLogger` - Application startup tracking

  ## Basic Usage

  ```elixir
  # Direct logging
  Logger.info("Simple message")
  Logger.error("Error occurred", error: reason)

  # Category logging (via CategoryLogger)
  Logger.api_info("API request received")
  Logger.cache_debug("Cache miss", key: "users:123")
  ```

  ## Metadata

  All logging functions accept metadata as the last argument (keyword list or map):

  ```elixir
  Logger.info("Processing item", item_id: 123, status: "pending")
  ```
  """
  @behaviour WandererNotifier.Shared.Logger.LoggerBehaviour

  require Logger

  alias WandererNotifier.Shared.Logger.CategoryLogger
  alias WandererNotifier.Shared.Logger.MetadataProcessor
  alias WandererNotifier.Shared.Logger.BatchLogger
  alias WandererNotifier.Shared.Logger.StartupLogger

  # Level constants for log_kv functions
  @level_debug :debug
  @level_info :info
  @level_warn :warning
  @level_error :error

  def debug(message), do: Logger.debug(message)

  def debug(message, metadata), do: Logger.debug(message, metadata)

  def info(message), do: Logger.info(message)

  def info(message, metadata), do: Logger.info(message, metadata)

  def warn(message), do: Logger.warning(message, [])

  def warn(message, metadata), do: Logger.warning(message, metadata)

  def error(message), do: Logger.error(message)

  def error(message, metadata), do: Logger.error(message, metadata)

  # Category-specific logging functions are delegated to CategoryLogger
  defdelegate api_error(message, metadata \\ []), to: CategoryLogger
  defdelegate processor_debug(message, metadata \\ []), to: CategoryLogger
  defdelegate processor_info(message, metadata \\ []), to: CategoryLogger
  defdelegate processor_warn(message, metadata \\ []), to: CategoryLogger
  defdelegate processor_error(message, metadata \\ []), to: CategoryLogger
  defdelegate processor_kv(message, value), to: CategoryLogger
  defdelegate notification_debug(message, metadata \\ []), to: CategoryLogger
  defdelegate notification_info(message, metadata \\ []), to: CategoryLogger
  defdelegate notification_warn(message, metadata \\ []), to: CategoryLogger
  defdelegate notification_error(message, metadata \\ []), to: CategoryLogger
  defdelegate notification_kv(message, value), to: CategoryLogger

  def log(level, category, message, metadata \\ []) do
    # Process and prepare metadata using MetadataProcessor
    metadata_with_diagnostics = MetadataProcessor.prepare_metadata(metadata, category)

    # Format message with category prefix
    formatted_message = "[#{category}] #{message}"

    # Add debug metadata if needed
    debug_suffix = MetadataProcessor.format_debug_metadata(metadata_with_diagnostics)
    enhanced_message = formatted_message <> debug_suffix

    # Log at the specified level
    Logger.log(level, enhanced_message, metadata_with_diagnostics)
  end

  # Metadata processing has been moved to MetadataProcessor module

  # Delegate all category-specific functions to CategoryLogger
  defdelegate api_debug(message, metadata \\ []), to: CategoryLogger
  defdelegate api_info(message, metadata \\ []), to: CategoryLogger
  defdelegate api_warn(message, metadata \\ []), to: CategoryLogger
  defdelegate api_kv(message, value), to: CategoryLogger

  defdelegate cache_debug(message, metadata \\ []), to: CategoryLogger
  defdelegate cache_info(message, metadata \\ []), to: CategoryLogger
  defdelegate cache_warn(message, metadata \\ []), to: CategoryLogger
  defdelegate cache_error(message, metadata \\ []), to: CategoryLogger
  defdelegate cache_kv(message, value), to: CategoryLogger

  defdelegate startup_info(message, metadata \\ []), to: CategoryLogger
  defdelegate startup_debug(message, metadata \\ []), to: CategoryLogger
  defdelegate startup_warn(message, metadata \\ []), to: CategoryLogger
  defdelegate startup_error(message, metadata \\ []), to: CategoryLogger
  defdelegate startup_kv(message, value), to: CategoryLogger

  defdelegate kill_debug(message, metadata \\ []), to: CategoryLogger
  defdelegate kill_info(message, metadata \\ []), to: CategoryLogger
  defdelegate kill_warn(message, metadata \\ []), to: CategoryLogger
  defdelegate kill_error(message, metadata \\ []), to: CategoryLogger
  defdelegate kill_warning(message, metadata \\ []), to: CategoryLogger
  defdelegate kill_kv(message, value), to: CategoryLogger

  defdelegate character_debug(message, metadata \\ []), to: CategoryLogger
  defdelegate character_info(message, metadata \\ []), to: CategoryLogger
  defdelegate character_warn(message, metadata \\ []), to: CategoryLogger
  defdelegate character_error(message, metadata \\ []), to: CategoryLogger
  defdelegate character_kv(message, value), to: CategoryLogger

  defdelegate system_debug(message, metadata \\ []), to: CategoryLogger
  defdelegate system_info(message, metadata \\ []), to: CategoryLogger
  defdelegate system_warn(message, metadata \\ []), to: CategoryLogger
  defdelegate system_error(message, metadata \\ []), to: CategoryLogger
  defdelegate system_kv(message, value), to: CategoryLogger

  defdelegate config_debug(message, metadata \\ []), to: CategoryLogger
  defdelegate config_info(message, metadata \\ []), to: CategoryLogger
  defdelegate config_warn(message, metadata \\ []), to: CategoryLogger
  defdelegate config_error(message, metadata \\ []), to: CategoryLogger
  defdelegate config_kv(message, value), to: CategoryLogger

  def set_context(metadata) do
    MetadataProcessor.set_context(metadata)
  end

  def with_trace_id(metadata \\ []) do
    MetadataProcessor.with_trace_id(metadata)
  end

  def generate_trace_id do
    MetadataProcessor.generate_trace_id()
  end

  def exception(level, category, message, exception, metadata \\ []) do
    # Create enhanced metadata with exception details
    enhanced_metadata =
      metadata
      |> MetadataProcessor.convert_to_keyword_list()
      |> Keyword.put(:exception, Exception.message(exception))
      |> Keyword.put(:stacktrace, get_exception_stacktrace(exception))

    # Log with enhanced metadata
    log(level, category, message, enhanced_metadata)
  end

  # Helper to get a stacktrace for an exception
  defp get_exception_stacktrace(_exception) do
    case Process.info(self(), :current_stacktrace) do
      {:current_stacktrace, stacktrace} ->
        Exception.format_stacktrace(stacktrace)

      _ ->
        "No stacktrace available"
    end
  end

  def log_kv(level, category, message, value) do
    # Create metadata from the value
    metadata = %{value: value}

    # Log with the extracted metadata
    log(level, category, message, metadata)
  end

  def log_full_data(level, category, message, data, metadata \\ []) do
    # Create enhanced metadata with full data
    enhanced_metadata =
      metadata
      |> MetadataProcessor.convert_to_keyword_list()
      |> Keyword.put(:full_data, data)

    # Log with enhanced metadata
    log(level, category, message, enhanced_metadata)
  end

  def info_kv(category, message, value), do: log_kv(@level_info, category, message, value)

  def debug_kv(category, message, value), do: log_kv(@level_debug, category, message, value)

  def warn_kv(category, message, value), do: log_kv(@level_warn, category, message, value)

  def error_kv(category, message, value), do: log_kv(@level_error, category, message, value)

  defdelegate websocket_kv(message, value), to: CategoryLogger
  defdelegate maintenance_kv(message, value), to: CategoryLogger

  # Batch logging functions delegated to BatchLogger
  defdelegate init_batch_logger, to: BatchLogger, as: :init

  defdelegate count_batch_event(category, details, log_immediately \\ false),
    to: BatchLogger,
    as: :count_event

  defdelegate flush_batch_logs, to: BatchLogger, as: :flush_all
  defdelegate flush_batch_category(category), to: BatchLogger, as: :flush_category
  defdelegate handle_batch_flush(interval \\ 5_000), to: BatchLogger, as: :handle_flush

  # Startup tracking functions delegated to StartupLogger
  defdelegate init_startup_tracker, to: StartupLogger, as: :init
  defdelegate begin_startup_phase(phase, message), to: StartupLogger, as: :begin_phase

  defdelegate record_startup_event(type, details, force_log \\ false),
    to: StartupLogger,
    as: :record_event

  defdelegate record_startup_error(message, details), to: StartupLogger, as: :record_error
  defdelegate complete_startup, to: StartupLogger, as: :complete

  defdelegate log_startup_state_change(type, message, details),
    to: StartupLogger,
    as: :log_state_change

  def log_with_timing(level, category, metadata \\ [], fun) do
    start_time = :os.system_time(:microsecond)
    result = fun.()
    end_time = :os.system_time(:microsecond)
    duration_us = end_time - start_time

    metadata
    |> MetadataProcessor.convert_to_keyword_list()
    |> Keyword.put(:duration_us, duration_us)
    |> then(fn metadata_with_timing ->
      log(level, category, "Operation completed", metadata_with_timing)
    end)

    result
  end

  defdelegate scheduler_debug(message, metadata \\ []), to: CategoryLogger
  defdelegate scheduler_info(message, metadata \\ []), to: CategoryLogger
  defdelegate scheduler_warn(message, metadata \\ []), to: CategoryLogger
  defdelegate scheduler_error(message, metadata \\ []), to: CategoryLogger
  defdelegate scheduler_kv(message, value), to: CategoryLogger

  defdelegate maintenance_debug(message, metadata \\ []), to: CategoryLogger
  defdelegate maintenance_info(message, metadata \\ []), to: CategoryLogger
  defdelegate maintenance_warn(message, metadata \\ []), to: CategoryLogger
  defdelegate maintenance_error(message, metadata \\ []), to: CategoryLogger
end
