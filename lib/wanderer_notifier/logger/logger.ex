defmodule WandererNotifier.Logger.Logger do
  @moduledoc """
  Enhanced and unified logging utility for WandererNotifier.

  This module serves as the central logging API for the entire application, providing:

  1. Consistent logging patterns with category-specific helpers
  2. Structured metadata handling that works reliably with both maps and keyword lists
  3. Key-value logging for configuration values and flags
  4. Batch logging support for high-volume events
  5. Startup phase tracking and logging

  ## Basic Usage

  Simple logging with categories:

  ```elixir
  # Basic logging
  Logger.info("Simple message")

  # Category-specific logging
  Logger.api_info("API request received")
  Logger.cache_debug("Cache miss", key: "users:123")

  # Key-value logging (ideal for flags and configuration)
  Logger.startup_kv("Status messages disabled", disabled_flag)
  ```

  ## Batch Logging

  For high-volume events, use batch logging to reduce log noise:

  ```elixir
  # Initialize batch logger
  Logger.init_batch_logger()

  # Count events (will be logged in batches)
  Logger.count_batch_event(:kill_received, %{system_id: "12345"})

  # Force flush when needed
  Logger.flush_batch_logs()
  ```

  ## Startup Tracking

  Track application startup phases:

  ```elixir
  # Initialize at application start
  Logger.init_startup_tracker()

  # Track phases
  Logger.begin_startup_phase(:dependencies, "Loading dependencies")

  # Record events
  Logger.record_startup_event(:feature_status, %{feature: "websocket", enabled: true}, true)

  # Complete startup
  Logger.complete_startup()
  ```

  ## Metadata

  All logging functions accept metadata as the last argument. This can be a keyword list or map:

  ```elixir
  Logger.info("Processing item", item_id: 123, status: "pending")
  ```

  Metadata is properly normalized regardless of format (map or keyword list).
  """
  @behaviour WandererNotifier.Logger.LoggerBehaviour

  require Logger

  # Category constants
  @category_api :api
  @category_websocket :websocket
  @category_kill :kill
  @category_cache :cache
  @category_startup :startup
  @category_config :config
  @category_maintenance :maintenance
  @category_scheduler :scheduler
  @category_processor :processor
  @category_notification :notification

  # Level constants
  @level_debug :debug
  @level_info :info
  @level_warn :warning
  @level_error :error

  # Batch logging state
  # 5 seconds
  @batch_log_interval 5_000

  def debug(message), do: Logger.debug(message)

  def debug(message, metadata), do: Logger.debug(message, metadata)

  def info(message), do: Logger.info(message)

  def info(message, metadata), do: Logger.info(message, metadata)

  def warn(message), do: Logger.warning(message, [])

  def warn(message, metadata), do: Logger.warning(message, metadata)

  def error(message), do: Logger.error(message)

  def error(message, metadata), do: Logger.error(message, metadata)

  def api_error(message, metadata \\ [])
  def api_error(message, metadata), do: Logger.error("[API] #{message}", metadata)
  def api_info(message, metadata \\ []), do: log(@level_info, @category_api, message, metadata)

  def processor_debug(message, metadata \\ [])

  def processor_debug(message, metadata),
    do: log(@level_debug, @category_processor, message, metadata)

  def processor_info(message, metadata \\ [])

  def processor_info(message, metadata),
    do: log(@level_info, @category_processor, message, metadata)

  def processor_warn(message, metadata \\ [])

  def processor_warn(message, metadata),
    do: log(@level_warn, @category_processor, message, metadata)

  def processor_error(message, metadata \\ [])

  def processor_error(message, metadata),
    do: log(@level_error, @category_processor, message, metadata)

  def notification_debug(message, metadata \\ [])

  def notification_debug(message, metadata),
    do: log(@level_debug, @category_notification, message, metadata)

  def notification_info(message, metadata \\ [])

  def notification_info(message, metadata),
    do: log(@level_info, @category_notification, message, metadata)

  def notification_warn(message, metadata \\ [])

  def notification_warn(message, metadata),
    do: log(@level_warn, @category_notification, message, metadata)

  def notification_error(message, metadata \\ [])

  def notification_error(message, metadata),
    do: log(@level_error, @category_notification, message, metadata)

  def log(level, category, message, metadata \\ []) do
    # Process and prepare metadata
    metadata_with_diagnostics = prepare_metadata(metadata, category)

    # Format message with category prefix
    formatted_message = "[#{category}] #{message}"

    # For debugging, add metadata keys if env var is set
    enhanced_message = maybe_add_debug_metadata(formatted_message, metadata_with_diagnostics)

    # Log at the specified level
    Logger.log(level, enhanced_message, metadata_with_diagnostics)
  end

  # Processes metadata to ensure proper format and adds diagnostics
  defp prepare_metadata(metadata, category) do
    # Convert to proper format
    converted_metadata = convert_metadata_to_keyword_list(metadata)

    # Add original type info
    metadata_with_type = add_metadata_type_info(metadata, converted_metadata)

    # Add category with proper formatting for visibility in the logs
    # Category will be printed as [CATEGORY=API] for better readability
    metadata_with_category = Keyword.put(metadata_with_type, :category, category)

    # Merge with Logger context, but ensure our category takes precedence
    Logger.metadata()
    # Remove existing category if present
    |> Keyword.delete(:category)
    # Add our metadata with correct category
    |> Keyword.merge(metadata_with_category)
  end

  # Adds metadata type information for debugging
  defp add_metadata_type_info(original_metadata, converted_metadata) do
    orig_type = determine_metadata_type(original_metadata)
    Keyword.put(converted_metadata, :orig_metadata_type, orig_type)
  end

  # Determines the type of the original metadata
  defp determine_metadata_type(metadata) do
    cond do
      is_map(metadata) ->
        "map"

      is_list(metadata) && metadata == [] ->
        "empty_list"

      is_list(metadata) && Enum.all?(metadata, &is_tuple/1) &&
          Enum.all?(metadata, fn {k, _v} -> is_atom(k) end) ->
        "keyword_list"

      is_list(metadata) ->
        "non_keyword_list"

      true ->
        "other_type:#{typeof(metadata)}"
    end
  end

  # Formats the log message with all metadata included
  defp maybe_add_debug_metadata(message, metadata) do
    # Format all metadata fields for the log message
    all_metadata = extract_metadata_for_debug(metadata, :full)

    message_with_data =
      if all_metadata != "", do: "#{message} (#{all_metadata})", else: message

    message_with_data
  end

  # Extracts and formats metadata for logging - shows both keys and values
  defp extract_metadata_for_debug(metadata, :full) do
    metadata
    |> Enum.reject(fn {k, _v} ->
      k in [:_metadata_source, :_metadata_warning, :_original_data, :_caller, :orig_metadata_type]
    end)
    |> Enum.map_join(", ", fn {k, v} ->
      formatted_value = format_value_for_debug(v)
      "#{k}=#{formatted_value}"
    end)
  end

  # Formats different value types for debug output
  defp format_value_for_debug(value) when is_binary(value),
    do: "\"#{String.slice(value, 0, 100)}\""

  defp format_value_for_debug(value) when is_list(value), do: "list[#{length(value)}]"
  defp format_value_for_debug(value) when is_map(value), do: "map{#{map_size(value)}}"
  defp format_value_for_debug(value), do: inspect(value, limit: 10)

  # Helper to convert metadata to keyword list
  defp convert_metadata_to_keyword_list(metadata) when is_map(metadata) do
    metadata
    |> Enum.map(fn {k, v} -> {safe_to_atom(k), v} end)
    |> Keyword.put(:_metadata_source, "map")
  end

  defp convert_metadata_to_keyword_list(metadata) when is_list(metadata) do
    cond do
      valid_keyword_list?(metadata) ->
        add_metadata_source(metadata, "keyword_list")

      metadata == [] ->
        create_empty_list_metadata()

      true ->
        handle_invalid_list(metadata)
    end
  end

  # Handle any other metadata type
  defp convert_metadata_to_keyword_list(metadata) do
    caller = get_caller_info()

    Logger.warning(
      "[LOGGER] Invalid metadata type #{inspect(metadata)} (#{inspect(typeof(metadata))})\nCaller: #{caller}"
    )

    [
      _metadata_source: "invalid_type",
      _metadata_warning: "Invalid metadata type converted to keyword list",
      _original_type: inspect(typeof(metadata)),
      _original_data: inspect(metadata),
      _caller: caller
    ]
  end

  defp valid_keyword_list?(metadata) do
    Enum.all?(metadata, &is_tuple/1) && Enum.all?(metadata, fn {k, _v} -> is_atom(k) end)
  end

  defp create_empty_list_metadata do
    [
      _metadata_source: "empty_list",
      _metadata_warning: "Empty list converted to keyword list"
    ]
  end

  defp handle_invalid_list(metadata) do
    caller = get_caller_info()
    log_invalid_list_warning(metadata, caller)
    convert_invalid_list_to_keyword_list(metadata, caller)
  end

  defp log_invalid_list_warning(metadata, caller) do
    Logger.warning(
      "[LOGGER] Non-keyword list passed as metadata! Convert to map. List: #{inspect(metadata)}\nCaller: #{caller}"
    )
  end

  defp convert_invalid_list_to_keyword_list(metadata, caller) do
    metadata
    |> Enum.with_index()
    |> Enum.map(fn {value, index} -> {"item_#{index}", value} end)
    |> Enum.into(%{})
    |> Enum.map(fn {k, v} -> {safe_to_atom(k), v} end)
    |> add_metadata_source("invalid_list_converted")
    |> Keyword.put(:_metadata_warning, "Non-keyword list converted to keyword list")
    |> Keyword.put(:_original_data, inspect(metadata))
    |> Keyword.put(:_caller, caller)
  end

  defp add_metadata_source(metadata, source) do
    Keyword.put(metadata, :_metadata_source, source)
  end

  # Helper to get type of value
  defp typeof(value) when is_binary(value), do: "string"
  defp typeof(value) when is_boolean(value), do: "boolean"
  defp typeof(value) when is_integer(value), do: "integer"
  defp typeof(value) when is_float(value), do: "float"
  defp typeof(value) when is_list(value), do: "list"
  defp typeof(value) when is_map(value), do: "map"
  defp typeof(value) when is_tuple(value), do: "tuple"
  defp typeof(value) when is_atom(value), do: "atom"
  defp typeof(value) when is_function(value), do: "function"
  defp typeof(value) when is_pid(value), do: "pid"
  defp typeof(value) when is_reference(value), do: "reference"
  defp typeof(value) when is_port(value), do: "port"
  defp typeof(_value), do: "unknown"

  # Get detailed caller information
  defp get_caller_info do
    case Process.info(self(), :current_stacktrace) do
      {:current_stacktrace, stacktrace} ->
        format_stacktrace(stacktrace)

      _ ->
        "unknown caller"
    end
  end

  # Format the caller information to show file and line
  defp format_stacktrace(stacktrace) do
    stacktrace
    |> Enum.drop_while(fn {mod, _fun, _args, _loc} ->
      mod
      |> inspect()
      |> String.contains?(["Logger", "WandererNotifier.Logger.Logger"])
    end)
    |> Enum.take(3)
    |> format_frames()
  end

  defp format_frames([]), do: "unknown caller"

  defp format_frames(frames) do
    frames
    |> Enum.map(fn {mod, fun, args, location} ->
      file = Keyword.get(location, :file, "unknown")
      line = Keyword.get(location, :line, "?")
      "#{inspect(mod)}.#{fun}/#{length(args)} at #{file}:#{line}"
    end)
    |> Enum.join("\n  ")
  end

  # Convert string or atom keys to atoms safely
  defp safe_to_atom(key) when is_atom(key), do: key

  defp safe_to_atom(key) when is_binary(key) do
    try do
      String.to_existing_atom(key)
    rescue
      ArgumentError ->
        # For known safe keys, we can create new atoms
        case key do
          "_metadata_source" -> :_metadata_source
          "_metadata_warning" -> :_metadata_warning
          "_original_type" -> :_original_type
          "_original_data" -> :_original_data
          "_caller" -> :_caller
          _ -> String.to_atom("metadata_#{key}")
        end
    end
  end

  defp safe_to_atom(key), do: String.to_atom("metadata_#{inspect(key)}")

  # API category helpers
  def api_debug(message, metadata \\ []), do: log(@level_debug, @category_api, message, metadata)

  def api_warn(message, metadata \\ []), do: log(@level_warn, @category_api, message, metadata)

  # WebSocket category helpers
  def websocket_debug(message, metadata \\ []),
    do: log(@level_debug, @category_websocket, message, metadata)

  def websocket_info(message, metadata \\ []),
    do: log(@level_info, @category_websocket, message, metadata)

  def websocket_warn(message, metadata \\ []),
    do: log(@level_warn, @category_websocket, message, metadata)

  def websocket_error(message, metadata \\ []),
    do: log(@level_error, @category_websocket, message, metadata)

  # Kill processing category helpers
  def kill_debug(message, metadata \\ []),
    do: log(@level_debug, @category_kill, message, metadata)

  def kill_info(message, metadata \\ []),
    do: log(@level_info, @category_kill, message, metadata)

  def kill_warn(message, metadata \\ []),
    do: log(@level_warn, @category_kill, message, metadata)

  def kill_error(message, metadata \\ []),
    do: log(@level_error, @category_kill, message, metadata)

  # Cache category helpers
  def cache_debug(message, metadata \\ []),
    do: log(@level_debug, @category_cache, message, metadata)

  def cache_info(message, metadata \\ []),
    do: log(@level_info, @category_cache, message, metadata)

  def cache_warn(message, metadata \\ []),
    do: log(@level_warn, @category_cache, message, metadata)

  def cache_error(message, metadata \\ []),
    do: log(@level_error, @category_cache, message, metadata)

  # Startup/Config helpers
  def startup_info(message, metadata \\ []),
    do: log(@level_info, @category_startup, message, metadata)

  def startup_debug(message, metadata \\ []),
    do: log(@level_debug, @category_startup, message, metadata)

  def startup_warn(message, metadata \\ []),
    do: log(@level_warn, @category_startup, message, metadata)

  def startup_error(message, metadata \\ []),
    do: log(@level_error, @category_startup, message, metadata)

  def config_info(message, metadata \\ []),
    do: log(@level_info, @category_config, message, metadata)

  def config_warn(message, metadata \\ []),
    do: log(@level_warn, @category_config, message, metadata)

  def config_error(message, metadata \\ []),
    do: log(@level_error, @category_config, message, metadata)

  def config_debug(message, metadata \\ []) do
    if should_log_debug?() do
      log(:debug, "CONFIG", message, metadata)
    end
  end

  # Maintenance category helpers
  def maintenance_debug(message, metadata \\ []),
    do: log(@level_debug, @category_maintenance, message, metadata)

  def maintenance_info(message, metadata \\ []),
    do: log(@level_info, @category_maintenance, message, metadata)

  def maintenance_warn(message, metadata \\ []),
    do: log(@level_warn, @category_maintenance, message, metadata)

  def maintenance_error(message, metadata \\ []),
    do: log(@level_error, @category_maintenance, message, metadata)

  # Scheduler category helpers
  def scheduler_debug(message, metadata \\ []),
    do: log(@level_debug, @category_scheduler, message, metadata)

  def scheduler_info(message, metadata \\ []),
    do: log(@level_info, @category_scheduler, message, metadata)

  def scheduler_warn(message, metadata \\ []),
    do: log(@level_warn, @category_scheduler, message, metadata)

  def scheduler_error(message, metadata \\ []),
    do: log(@level_error, @category_scheduler, message, metadata)

  def scheduler_log(level, message, metadata \\ [])
      when level in [:debug, :info, :warning, :warn, :error] do
    # Normalize :warning to :warn for consistency
    normalized_level = if level == :warning, do: :warn, else: level
    log(normalized_level, @category_scheduler, message, metadata)
  end

  # Kill processing category
  # Use kill_warn consistently instead of kill_warning
  def kill_warning(message, metadata \\ []),
    do: kill_warn(message, metadata)

  def set_context(metadata) do
    # Convert to keyword list and normalize
    normalized_metadata = convert_metadata_to_keyword_list(metadata)

    # Set the metadata for the current process
    Logger.metadata(normalized_metadata)
  end

  def with_trace_id(metadata \\ []) do
    trace_id = generate_trace_id()

    # Normalize metadata and add trace_id
    normalized_metadata =
      metadata
      |> convert_metadata_to_keyword_list()
      |> Keyword.put(:trace_id, trace_id)

    # Set context with the new metadata
    set_context(normalized_metadata)

    # Return the trace ID for reference
    trace_id
  end

  def generate_trace_id do
    # Generate a unique trace ID
    :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
  end

  def exception(level, category, message, exception, metadata \\ []) do
    # Create enhanced metadata with exception details
    enhanced_metadata =
      metadata
      |> convert_metadata_to_keyword_list()
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
      |> convert_metadata_to_keyword_list()
      |> Keyword.put(:full_data, data)

    # Log with enhanced metadata
    log(level, category, message, enhanced_metadata)
  end

  def info_kv(category, message, value), do: log_kv(@level_info, category, message, value)

  def debug_kv(category, message, value), do: log_kv(@level_debug, category, message, value)

  def warn_kv(category, message, value), do: log_kv(@level_warn, category, message, value)

  def error_kv(category, message, value), do: log_kv(@level_error, category, message, value)

  def config_kv(message, value), do: info_kv(@category_config, message, value)

  def startup_kv(message, value), do: info_kv(@category_startup, message, value)

  def cache_kv(message, value), do: info_kv(@category_cache, message, value)

  def websocket_kv(message, value), do: info_kv(@category_websocket, message, value)

  def api_kv(message, value), do: info_kv(@category_api, message, value)

  def maintenance_kv(message, value), do: info_kv(@category_maintenance, message, value)

  # ------------------------------------------------------------
  # Batch Logging Support
  # ------------------------------------------------------------

  def init_batch_logger do
    # Log that batch logging is being initialized
    debug("Initializing batch logger")

    # Schedule periodic flush
    Process.send_after(self(), :flush_batch_logs, @batch_log_interval)

    :ok
  end

  def count_batch_event(_category, _details, _log_immediately \\ false) do
    # For now, just log immediately with a batch indicator
    # log(@level_info, category, "Batch event", Map.merge(details, %{batch: true}))
    :ok
  end

  def flush_batch_logs do
    debug("Flushing all batch logs")
    :ok
  end

  def flush_batch_category(category) do
    debug("Flushing batch logs for category: #{category}")
    :ok
  end

  def handle_batch_flush(_state) do
    flush_batch_logs()
    Process.send_after(self(), :flush_batch_logs, @batch_log_interval)
    :ok
  end

  # ------------------------------------------------------------
  # Startup Tracking Support
  # ------------------------------------------------------------

  def init_startup_tracker do
    debug("Initializing startup tracker")
    :ok
  end

  def begin_startup_phase(phase, message) do
    info("[Startup] Beginning phase: #{phase}", %{
      phase: phase,
      message: message,
      timestamp: DateTime.utc_now()
    })

    :ok
  end

  def record_startup_event(type, details, force_log \\ false) do
    level = if force_log, do: @level_info, else: @level_debug

    log(
      level,
      @category_startup,
      "Startup event: #{type}",
      Map.merge(details, %{event_type: type})
    )

    :ok
  end

  def record_startup_error(message, details) do
    error("[Startup] #{message}", details)
    :ok
  end

  def complete_startup do
    info("[Startup] Application startup complete", %{timestamp: DateTime.utc_now()})
    :ok
  end

  def log_startup_state_change(type, message, details) do
    info("[Startup] State change: #{type} - #{message}", details)
    :ok
  end

  defp should_log_debug? do
    WandererNotifier.Config.debug_logging_enabled?()
  end

  def log_with_timing(level, category, metadata \\ [], fun) do
    start_time = :os.system_time(:microsecond)
    result = fun.()
    end_time = :os.system_time(:microsecond)
    duration_us = end_time - start_time

    metadata
    |> convert_metadata_to_keyword_list()
    |> Keyword.put(:duration_us, duration_us)
    |> then(fn metadata_with_timing ->
      log(level, category, "Operation completed", metadata_with_timing)
    end)

    result
  end
end
