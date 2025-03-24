defmodule WandererNotifier.Logger do
  @moduledoc """
  Enhanced logging utility for WandererNotifier.

  Provides consistent logging patterns, structured metadata, and helper functions
  to improve log quality and reduce noise.
  """
  require Logger

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

  @doc """
  Logs a message at the specified level with structured metadata.

  ## Examples

      iex> WandererNotifier.Logger.log(:info, "KILL", "Processed killmail", kill_id: "12345")
      :ok
  """
  def log(level, category, message, metadata \\ []) do
    # Process and prepare metadata
    metadata_with_diagnostics = prepare_metadata(metadata, category)

    # Format message with category prefix
    formatted_message = format_log_message(category, message, metadata_with_diagnostics)

    # Log at the specified level
    Logger.log(level, formatted_message, metadata_with_diagnostics)
  end

  # Processes metadata to ensure proper format and adds diagnostics
  defp prepare_metadata(metadata, category) do
    # Convert to proper format
    converted_metadata = convert_metadata_to_keyword_list(metadata)

    # Add original type info
    metadata_with_type = add_metadata_type_info(metadata, converted_metadata)

    # Add category
    metadata_with_category = Keyword.put(metadata_with_type, :category, category)

    # Merge with Logger context
    Keyword.merge(Logger.metadata(), metadata_with_category)
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
  defp format_log_message(category, message, metadata) do
    base_message = "[#{category}] #{message}"

    if System.get_env("WANDERER_DEBUG_LOGGING") == "true" do
      metadata_keys = extract_metadata_keys(metadata)
      "#{base_message} [META-KEYS:#{metadata_keys}]"
    else
      base_message
    end
  end

  # Extracts and formats metadata keys for debug logging
  defp extract_metadata_keys(metadata) do
    metadata
    |> Enum.map(fn {k, _} -> k end)
    |> inspect()
    # Limit length for readability
    |> String.slice(0, 100)
  end

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

        # Convert the data to a keyword list with diagnostics
        [
          _metadata_source: "invalid_list",
          _metadata_warning: "Non-keyword list converted to keyword list",
          _original_data: inspect(metadata),
          _caller: caller
        ]
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
          String.contains?(inspect(mod), "WandererNotifier.Logger")
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
  def api_error(message, metadata \\ []), do: log(@level_error, @category_api, message, metadata)

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

  def kill_info(message, metadata \\ []), do: log(@level_info, @category_kill, message, metadata)
  def kill_warn(message, metadata \\ []), do: log(@level_warn, @category_kill, message, metadata)

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

  # Processor category helpers
  def processor_debug(message, metadata \\ []),
    do: log(@level_debug, @category_processor, message, metadata)

  def processor_info(message, metadata \\ []),
    do: log(@level_info, @category_processor, message, metadata)

  def processor_warn(message, metadata \\ []),
    do: log(@level_warn, @category_processor, message, metadata)

  def processor_error(message, metadata \\ []),
    do: log(@level_error, @category_processor, message, metadata)

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

  def config_debug(message, metadata \\ []),
    do: log(@level_debug, @category_config, message, metadata)

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
        WandererNotifier.Logger.log(unquote(level), unquote(category), message, unquote(metadata))
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

      iex> WandererNotifier.Logger.enable_debug_logging(true)
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
end
