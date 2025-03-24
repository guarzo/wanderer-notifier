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
    # Convert map metadata to keyword list if needed
    metadata = convert_metadata_to_keyword_list(metadata)

    # Ensure the category is in the metadata
    metadata = Keyword.put(metadata, :category, category)

    # Format the message with category prefix
    formatted_message = "[#{category}] #{message}"

    # Merge with existing metadata from Logger context
    metadata = Keyword.merge(Logger.metadata(), metadata)

    # Log at the specified level
    Logger.log(level, formatted_message, metadata)
  end

  # Helper to convert metadata to keyword list
  defp convert_metadata_to_keyword_list(metadata) when is_map(metadata) do
    Enum.map(metadata, fn {k, v} -> {to_atom(k), v} end)
  end

  defp convert_metadata_to_keyword_list(metadata) when is_list(metadata) do
    metadata
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
end
