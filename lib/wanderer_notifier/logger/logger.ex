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

  # This module implements the WandererNotifier.Logger.Behaviour interface
  @behaviour WandererNotifier.Logger.Behaviour

  require Logger
  alias WandererNotifier.Config.Debug
  alias WandererNotifier.Logger.Logger.BatchLogger
  alias WandererNotifier.Logger.StartupTracker

  # Log categories as module attributes for consistency
  @category_api "API"
  @category_websocket "WEBSOCKET"
  @category_kill "KILL"
  @category_persistence "PERSISTENCE"
  @category_processor "PROCESSOR"
  @category_cache "CACHE"
  @category_startup "STARTUP"
  @category_config "CONFIG"
  @category_maintenance "MAINTENANCE"
  @category_scheduler "SCHEDULER"
  @category_chart "CHART"

  # Log levels mapped to their appropriate use cases
  # Detailed troubleshooting information
  @level_debug :debug
  # Normal operational events
  @level_info :info
  # Potential issues that aren't errors
  @level_warn :warning
  # Errors that affect functionality
  @level_error :error

  @impl true
  def debug(message), do: Logger.debug(message)

  @impl true
  def debug(message, metadata), do: Logger.debug(message, metadata)

  @impl true
  def info(message), do: Logger.info(message)

  @impl true
  def info(message, metadata), do: Logger.info(message, metadata)

  @impl true
  def warn(message), do: Logger.warning(message)

  @impl true
  def warn(message, metadata), do: Logger.warning(message, metadata)

  @impl true
  def error(message), do: Logger.error(message)

  @impl true
  def error(message, metadata), do: Logger.error(message, metadata)

  @impl true
  def api_error(message, metadata \\ [])
  def api_error(message, metadata), do: Logger.error("[API] #{message}", metadata)

  @impl true
  def processor_debug(message, metadata \\ [])

  def processor_debug(message, metadata),
    do: log(@level_debug, @category_processor, message, metadata)

  @impl true
  def processor_info(message, metadata \\ [])

  def processor_info(message, metadata),
    do: log(@level_info, @category_processor, message, metadata)

  @impl true
  def processor_warn(message, metadata \\ [])

  def processor_warn(message, metadata),
    do: log(@level_warn, @category_processor, message, metadata)

  @impl true
  def processor_error(message, metadata \\ [])

  def processor_error(message, metadata),
    do: log(@level_error, @category_processor, message, metadata)

  @impl true
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

  # Formats the log message with optional debug information
  defp maybe_add_debug_metadata(message, metadata) do
    # Always include key metadata fields in the log message, regardless of debug mode
    # Extract the important fields into a simple string
    important_fields = extract_important_metadata(metadata)

    message_with_data =
      if important_fields != "", do: "#{message} #{important_fields}", else: message

    # If debug mode is enabled, add full detailed metadata
    if should_log_debug?() do
      # Include both keys and values in debug mode
      metadata_summary = extract_metadata_for_debug(metadata)
      "#{message_with_data} [META:#{metadata_summary}]"
    else
      message_with_data
    end
  end

  # Extract important metadata for formatted logging
  defp extract_important_metadata(metadata) do
    # Define which keys are considered important for different log types
    important_keys = [
      :character_id,
      :character_name,
      :solar_system_id,
      :solar_system_name,
      :region_name,
      :kill_id,
      :status,
      :reason,
      :error,
      :count,
      :trace_id
    ]

    # Filter important metadata
    important_data =
      metadata
      |> Enum.filter(fn {k, _v} -> k in important_keys end)
      # Limit to 5 most important items
      |> Enum.take(5)

    # Format empty data
    if Enum.empty?(important_data) do
      ""
    else
      # Format them nicely for the log message
      "(" <>
        Enum.map_join(important_data, ", ", fn {k, v} -> "#{k}=#{inspect(v)}" end) <>
        ")"
    end
  end

  # Extracts and formats metadata for debug logging - shows both keys and values
  defp extract_metadata_for_debug(metadata) do
    metadata
    |> Enum.map_join(", ", fn {k, v} ->
      # Format value based on type for better readability
      formatted_value = format_value_for_debug(v)
      "#{k}=#{formatted_value}"
    end)
    # Limit length for readability
    |> String.slice(0, 200)
  end

  # Formats different value types for debug output
  defp format_value_for_debug(value) when is_binary(value),
    do: "\"#{String.slice(value, 0, 30)}\""

  defp format_value_for_debug(value) when is_list(value), do: "list[#{length(value)}]"
  defp format_value_for_debug(value) when is_map(value), do: "map{#{map_size(value)}}"
  defp format_value_for_debug(value), do: inspect(value, limit: 10)

  # Helper to convert metadata to keyword list
  defp convert_metadata_to_keyword_list(metadata) when is_map(metadata) do
    # Map is converted to keyword list
    map_metadata = Enum.map(metadata, fn {k, v} -> {to_atom(k), v} end)
    # Add diagnostics to show this was a map
    Keyword.put(map_metadata, :_metadata_source, "map")
  end

  defp convert_metadata_to_keyword_list(metadata) when is_list(metadata) do
    cond do
      # Valid keyword list
      Enum.all?(metadata, &is_tuple/1) && Enum.all?(metadata, fn {k, _v} -> is_atom(k) end) ->
        # Add diagnostics to show this was a keyword list
        Keyword.put(metadata, :_metadata_source, "keyword_list")

      # Empty list
      metadata == [] ->
        # Convert empty list to empty map with diagnostic
        [
          _metadata_source: "empty_list",
          _metadata_warning: "Empty list converted to keyword list"
        ]

      # Non-keyword list (the problematic case)
      true ->
        # Get caller information for debugging
        caller = get_caller_info()

        # Log warning about non-keyword list with detailed caller information
        Logger.warning(
          "[LOGGER] Non-keyword list passed as metadata! Convert to map. List: #{inspect(metadata)}\nCaller: #{caller}"
        )

        # Convert the non-keyword list to a map with indices as keys, then to keyword list
        converted_data =
          metadata
          |> Enum.with_index()
          |> Enum.map(fn {value, index} -> {"item_#{index}", value} end)
          |> Enum.into(%{})
          |> Enum.map(fn {k, v} -> {to_atom(k), v} end)

        # Add diagnostics about the conversion
        converted_data
        |> Keyword.put(:_metadata_source, "invalid_list_converted")
        |> Keyword.put(:_metadata_warning, "Non-keyword list converted to keyword list")
        |> Keyword.put(:_original_data, inspect(metadata))
        |> Keyword.put(:_caller, caller)
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
    # Filter out Logger frames to focus on the actual caller
    relevant_frames =
      stacktrace
      |> Enum.drop_while(fn {mod, _fun, _args, _loc} ->
        String.contains?(inspect(mod), "Logger") ||
          String.contains?(inspect(mod), "WandererNotifier.Logger.Logger")
      end)
      # Take first 3 relevant frames
      |> Enum.take(3)

    case relevant_frames do
      [] ->
        "unknown caller"

      frames ->
        Enum.map_join(frames, "\n  ", fn {mod, fun, args, location} ->
          file = Keyword.get(location, :file, "unknown")
          line = Keyword.get(location, :line, "?")
          "#{inspect(mod)}.#{fun}/#{length(args)} at #{file}:#{line}"
        end)
    end
  end

  # Convert string or atom keys to atoms safely
  defp to_atom(key) when is_atom(key), do: key

  defp to_atom(key) when is_binary(key) do
    String.to_existing_atom(key)
  rescue
    ArgumentError -> String.to_atom(key)
  end

  # API category helpers
  @impl true
  def api_debug(message, metadata \\ []), do: log(@level_debug, @category_api, message, metadata)

  @impl true
  def api_info(message, metadata \\ []), do: log(@level_info, @category_api, message, metadata)

  @impl true
  def api_warn(message, metadata \\ []), do: log(@level_warn, @category_api, message, metadata)

  # WebSocket category helpers
  @impl true
  def websocket_debug(message, metadata \\ []),
    do: log(@level_debug, @category_websocket, message, metadata)

  @impl true
  def websocket_info(message, metadata \\ []),
    do: log(@level_info, @category_websocket, message, metadata)

  @impl true
  def websocket_warn(message, metadata \\ []),
    do: log(@level_warn, @category_websocket, message, metadata)

  @impl true
  def websocket_error(message, metadata \\ []),
    do: log(@level_error, @category_websocket, message, metadata)

  # Kill processing category helpers
  @impl true
  def kill_debug(message, metadata \\ [])

  def kill_debug(message, metadata) do
    # Always log kill debug at info level to ensure visibility
    log(@level_debug, @category_kill, "DEBUG: #{message}", metadata)
  end

  @impl true
  def kill_info(message, metadata \\ [])

  def kill_info(message, metadata) do
    log(@level_info, @category_kill, message, metadata)
  end

  @impl true
  def kill_warn(message, metadata \\ [])

  def kill_warn(message, metadata) do
    log(@level_warn, @category_kill, message, metadata)
  end

  @impl true
  def kill_error(message, metadata \\ [])

  def kill_error(message, metadata) do
    log(@level_error, @category_kill, message, metadata)
  end

  # Persistence category helpers
  @impl true
  def persistence_debug(message, metadata \\ []),
    do: log(@level_debug, @category_persistence, message, metadata)

  @impl true
  def persistence_info(message, metadata \\ []),
    do: log(@level_info, @category_persistence, message, metadata)

  @impl true
  def persistence_warn(message, metadata \\ []),
    do: log(@level_warn, @category_persistence, message, metadata)

  @impl true
  def persistence_error(message, metadata \\ []),
    do: log(@level_error, @category_persistence, message, metadata)

  # Cache category helpers
  @impl true
  def cache_debug(message, metadata \\ []),
    do: log(@level_debug, @category_cache, message, metadata)

  @impl true
  def cache_info(message, metadata \\ []),
    do: log(@level_info, @category_cache, message, metadata)

  @impl true
  def cache_warn(message, metadata \\ []),
    do: log(@level_warn, @category_cache, message, metadata)

  @impl true
  def cache_error(message, metadata \\ []),
    do: log(@level_error, @category_cache, message, metadata)

  # Startup/Config helpers
  @impl true
  def startup_info(message, metadata \\ []),
    do: log(@level_info, @category_startup, message, metadata)

  @impl true
  def startup_debug(message, metadata \\ []),
    do: log(@level_debug, @category_startup, message, metadata)

  @impl true
  def startup_warn(message, metadata \\ []),
    do: log(@level_warn, @category_startup, message, metadata)

  @impl true
  def startup_error(message, metadata \\ []),
    do: log(@level_error, @category_startup, message, metadata)

  @impl true
  def config_info(message, metadata \\ []),
    do: log(@level_info, @category_config, message, metadata)

  @impl true
  def config_warn(message, metadata \\ []),
    do: log(@level_warn, @category_config, message, metadata)

  @impl true
  def config_error(message, metadata \\ []),
    do: log(@level_error, @category_config, message, metadata)

  @impl true
  def config_debug(message, metadata \\ []) do
    if should_log_debug?() do
      log(:debug, "CONFIG", message, metadata)
    end
  end

  # Maintenance category helpers
  @impl true
  def maintenance_debug(message, metadata \\ []),
    do: log(@level_debug, @category_maintenance, message, metadata)

  @impl true
  def maintenance_info(message, metadata \\ []),
    do: log(@level_info, @category_maintenance, message, metadata)

  @impl true
  def maintenance_warn(message, metadata \\ []),
    do: log(@level_warn, @category_maintenance, message, metadata)

  @impl true
  def maintenance_error(message, metadata \\ []),
    do: log(@level_error, @category_maintenance, message, metadata)

  # Scheduler category helpers
  @impl true
  def scheduler_debug(message, metadata \\ []),
    do: log(@level_debug, @category_scheduler, message, metadata)

  @impl true
  def scheduler_info(message, metadata \\ []),
    do: log(@level_info, @category_scheduler, message, metadata)

  @impl true
  def scheduler_warn(message, metadata \\ []),
    do: log(@level_warn, @category_scheduler, message, metadata)

  @impl true
  def scheduler_error(message, metadata \\ []),
    do: log(@level_error, @category_scheduler, message, metadata)

  @doc """
  Logs a scheduler message at the specified level.
  This allows for dynamic log level selection.
  """
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

  # Persistence processing category
  def persistence_warning(message, metadata \\ []),
    do: persistence_warn(message, metadata)

  @impl true
  def set_context(metadata) do
    # Convert to keyword list and normalize
    normalized_metadata = convert_metadata_to_keyword_list(metadata)

    # Set the metadata for the current process
    Logger.metadata(normalized_metadata)
  end

  @impl true
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

  @impl true
  def generate_trace_id do
    # Generate a unique trace ID
    :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
  end

  @impl true
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

  @impl true
  def log_kv(level, category, message, value) do
    # Create metadata from the value
    metadata = %{value: value}

    # Log with the extracted metadata
    log(level, category, message, metadata)
  end

  @impl true
  def log_full_data(level, category, message, data, metadata \\ []) do
    # Create enhanced metadata with full data
    enhanced_metadata =
      metadata
      |> convert_metadata_to_keyword_list()
      |> Keyword.put(:full_data, data)

    # Log with enhanced metadata
    log(level, category, message, enhanced_metadata)
  end

  @impl true
  def info_kv(category, message, value), do: log_kv(@level_info, category, message, value)

  @impl true
  def debug_kv(category, message, value), do: log_kv(@level_debug, category, message, value)

  @impl true
  def warn_kv(category, message, value), do: log_kv(@level_warn, category, message, value)

  @impl true
  def error_kv(category, message, value), do: log_kv(@level_error, category, message, value)

  @impl true
  def config_kv(message, value), do: info_kv(@category_config, message, value)

  @impl true
  def startup_kv(message, value), do: info_kv(@category_startup, message, value)

  @impl true
  def cache_kv(message, value), do: info_kv(@category_cache, message, value)

  @impl true
  def websocket_kv(message, value), do: info_kv(@category_websocket, message, value)

  @impl true
  def api_kv(message, value), do: info_kv(@category_api, message, value)

  @impl true
  def maintenance_kv(message, value), do: info_kv(@category_maintenance, message, value)

  # ------------------------------------------------------------
  # Batch Logging Support
  # ------------------------------------------------------------

  @doc """
  Initializes the batch logger system.
  Should be called during application startup.
  """
  def init_batch_logger do
    BatchLogger.init()
  end

  @doc """
  Counts an event occurrence, batching it for later logging.

  ## Parameters

  - category: The event category (atom)
  - details: Map of event details used to group similar events
  - log_immediately: Whether to log immediately if count reaches threshold

  ## Examples

      iex> WandererNotifier.Logger.Logger.count_batch_event(:kill_received, %{system_id: "12345"})
      :ok
  """
  def count_batch_event(category, details \\ %{}, log_immediately \\ false) do
    BatchLogger.count_event(category, details, log_immediately)
  end

  @doc """
  Forces an immediate flush of all pending batch log events.
  """
  def flush_batch_logs do
    BatchLogger.flush_all()
  end

  @doc """
  Forces an immediate flush of a specific event category.
  """
  def flush_batch_category(category) do
    BatchLogger.flush_category(category)
  end

  @doc """
  Handles the periodic flush message for batch logging.
  This should be called by the process receiving the `:flush_batch_logs` message.
  """
  def handle_batch_flush(state) do
    BatchLogger.handle_info(:flush_batch_logs, state)
  end

  # ------------------------------------------------------------
  # Startup Tracking Support
  # ------------------------------------------------------------

  @doc """
  Initializes the startup tracker.
  Should be called at the very beginning of application startup.
  Returns the initial state for the startup tracker.
  """
  def init_startup_tracker do
    StartupTracker.init()
  end

  @doc """
  Begins a new startup phase.

  ## Parameters

  - phase: The phase to begin
  - message: Optional message about this phase
  """
  def begin_startup_phase(phase, message \\ nil) do
    StartupTracker.begin_phase(phase, message)
  end

  @doc """
  Records a startup event without necessarily logging it.
  Events are accumulated and may be summarized later.

  ## Parameters

  - type: The type of event
  - details: Map of event details
  - force_log: If true, will log immediately regardless of significance
  """
  def record_startup_event(type, details \\ %{}, force_log \\ false) do
    StartupTracker.record_event(type, details, force_log)
  end

  @doc """
  Records an error during startup.
  Errors are always logged immediately.

  ## Parameters

  - message: Error message
  - details: Additional error details
  """
  def record_startup_error(message, details \\ %{}) do
    StartupTracker.record_error(message, details)
  end

  @doc """
  Completes the startup process and logs a summary.
  """
  def complete_startup do
    StartupTracker.complete_startup()
  end

  @doc """
  Logs a significant state change during startup.
  These are always logged immediately.

  ## Parameters

  - type: The type of state change
  - message: The message about the state change
  - details: Additional details
  """
  def log_startup_state_change(type, message, details \\ %{}) do
    StartupTracker.log_state_change(type, message, details)
  end

  defp should_log_debug? do
    Debug.debug_logging_enabled?()
  end

  # Chart category helpers
  @impl true
  def chart_debug(message, metadata \\ []),
    do: log(@level_debug, @category_chart, message, metadata)

  @impl true
  def chart_info(message, metadata \\ []),
    do: log(@level_info, @category_chart, message, metadata)

  @impl true
  def chart_warn(message, metadata \\ []),
    do: log(@level_warn, @category_chart, message, metadata)

  @impl true
  def chart_error(message, metadata \\ []),
    do: log(@level_error, @category_chart, message, metadata)
end
