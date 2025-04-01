defmodule WandererNotifier.Logger.Logger do
  @moduledoc """
  Enhanced logging utility for WandererNotifier.

  Provides consistent logging patterns, structured metadata, and helper functions
  to improve log quality and reduce noise.
  """
  require Logger
  alias WandererNotifier.Config.Debug

  @behaviour WandererNotifier.Logger.Behaviour

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
  def info(message), do: Logger.info(message)

  @impl true
  def warn(message), do: Logger.warning(message)

  @impl true
  def error(message), do: Logger.error(message)

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

  @doc """
  Logs a message at the specified level with structured metadata.

  ## Examples

      iex> WandererNotifier.Logger.Logger.log(:info, "KILL", "Processed killmail", kill_id: "12345")
      :ok
  """
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

  # Extract important metadata to always include in log messages
  defp extract_important_metadata(metadata) do
    # List of important fields that should always be shown in logs
    important_keys = [
      :character_id,
      :kill_id,
      :system_id,
      :error,
      :reason,
      :start_str,
      :end_str,
      :count,
      :status_code
    ]

    # Filter only important fields that exist in the metadata
    important_data = Enum.filter(metadata, fn {k, _v} -> k in important_keys end)

    # Format them nicely for the log message
    if Enum.empty?(important_data) do
      ""
    else
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
  def api_debug(message, metadata \\ []), do: log(@level_debug, @category_api, message, metadata)
  def api_info(message, metadata \\ []), do: log(@level_info, @category_api, message, metadata)
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

  # Persistence category helpers
  def persistence_debug(message, metadata \\ []),
    do: log(@level_debug, @category_persistence, message, metadata)

  def persistence_info(message, metadata \\ []),
    do: log(@level_info, @category_persistence, message, metadata)

  def persistence_warn(message, metadata \\ []),
    do: log(@level_warn, @category_persistence, message, metadata)

  def persistence_error(message, metadata \\ []),
    do: log(@level_error, @category_persistence, message, metadata)

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

  @doc """
  Log debug configuration information.
  Only outputs if WANDERER_DEBUG_LOGGING=true.
  """
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

  @doc """
  Sets metadata in the Logger process dictionary.
  Provides a consistent way to add context to logs.
  """
  def set_context(metadata) do
    Logger.metadata(metadata)
  end

  @doc """
  Adds a trace ID to the current process's logger metadata.
  Useful for correlating logs across different processes.
  """
  def with_trace_id(metadata \\ []) do
    trace_id = generate_trace_id()
    metadata = Keyword.put(metadata, :trace_id, trace_id)
    Logger.metadata(metadata)
    trace_id
  end

  @doc """
  Generates a new trace ID for tracking related log entries.
  """
  def generate_trace_id do
    Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)
  end

  @doc """
  Creates a function that lazily evaluates expensive log messages.
  Use this to avoid the overhead of constructing complex log messages
  when the log level would cause them to be discarded.
  """
  defmacro lazy_log(level, category, message_func, metadata \\ []) do
    quote do
      require Logger

      if Logger.enabled?(unquote(level)) do
        message = unquote(message_func).()

        Logger.log(
          unquote(level),
          unquote(category),
          message,
          unquote(metadata)
        )
      end
    end
  end

  @doc """
  Logs an exception with a proper stack trace.
  """
  def exception(level, category, message, exception, metadata \\ []) do
    exception_message = Exception.message(exception)
    full_message = "#{message}: #{exception_message}"

    # We can't use __STACKTRACE__ here since we're not in a rescue block,
    # so we'll rely on metadata[:stacktrace] if provided or an empty string
    metadata =
      if Keyword.has_key?(metadata, :stacktrace) do
        metadata
      else
        Keyword.put(metadata, :stacktrace, "")
      end

    log(level, category, full_message, metadata)
  end

  @doc """
  Enables or disables debug logging to help diagnose metadata issues.

  Call this function with true to enable enhanced logging that will show
  metadata keys in log messages. Call with false to disable.

  ## Examples

      iex> WandererNotifier.Logger.Logger.enable_debug_logging(true)
      :ok
  """
  def enable_debug_logging(enable) when is_boolean(enable) do
    if enable do
      System.put_env("WANDERER_DEBUG_LOGGING", "true")
      Logger.configure(level: :debug)
      Logger.info("Logger debug mode ENABLED - metadata keys will be visible in logs")
    else
      System.put_env("WANDERER_DEBUG_LOGGING", "false")
      Logger.info("Logger debug mode DISABLED")
    end

    :ok
  end

  defp should_log_debug? do
    Debug.debug_logging_enabled?()
  end
end
