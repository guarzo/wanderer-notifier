defmodule WandererNotifier.Core.Logger.BatchLogger do
  @moduledoc """
  Provides batched logging functionality with counters for repetitive log messages.

  This module allows logging similar messages in batches with counters instead of
  individual entries, significantly reducing log volume for high-frequency operations.

  ## Features

  - Accumulates similar log messages and logs them in batches
  - Uses counters to track occurrences of similar events
  - Periodically flushes logs to ensure visibility
  - Thread-safe using process-based state

  ## Examples

  ```elixir
  # Track a kill received event (will be batched)
  BatchLogger.count_event(:kill_received, %{system_id: "12345"})

  # Force immediate flush of all pending events
  BatchLogger.flush_all()
  ```
  """

  require Logger
  alias WandererNotifier.Core.Logger, as: AppLogger

  # Flush logs every 5 seconds
  @flush_interval 5_000

  # Event categories - each one defines a separate counter
  @event_categories [
    # Killmail events received from websocket
    :kill_received,
    # System tracking checks
    :system_tracked,
    # Character tracking checks
    :character_tracked,
    # Cache hit events
    :cache_hit,
    # Cache miss events
    :cache_miss,
    # Notification events
    :notification_sent
  ]

  # ------------------------------------------------------------
  # Public API
  # ------------------------------------------------------------

  @doc """
  Initializes the batch logger system.
  Should be called during application startup.
  """
  def init do
    # Initialize counters as empty maps in the process dictionary
    Enum.each(@event_categories, fn category ->
      Process.put({:batch_logger, category}, %{})
    end)

    # Schedule the first periodic flush
    schedule_flush()

    :ok
  end

  @doc """
  Counts an event occurrence, batching it for later logging.

  ## Parameters

  - category: The event category (atom)
  - details: Map of event details used to group similar events
  - log_immediately: Whether to log immediately if count reaches threshold

  ## Returns

  - :ok

  ## Examples

  ```elixir
  BatchLogger.count_event(:kill_received, %{system_id: system_id})
  ```
  """
  def count_event(category, details \\ %{}, log_immediately \\ false) do
    # Ensure category is valid
    if category not in @event_categories do
      raise ArgumentError, "Invalid event category: #{category}"
    end

    # Get the current counters for this category
    counters = Process.get({:batch_logger, category}) || %{}

    # Create a key based on the details map
    event_key = create_event_key(details)

    # Increment the counter for this event
    new_counters = Map.update(counters, event_key, 1, &(&1 + 1))

    # Store the updated counters
    Process.put({:batch_logger, category}, new_counters)

    # Get the current count
    current_count = Map.get(new_counters, event_key)

    # Check if we should log immediately (count threshold reached or force immediate)
    if log_immediately || should_log_now?(current_count) do
      flush_category(category)
    end

    :ok
  end

  @doc """
  Forces an immediate flush of all pending log events.
  """
  def flush_all do
    Enum.each(@event_categories, &flush_category/1)
    :ok
  end

  @doc """
  Forces an immediate flush of a specific event category.
  """
  def flush_category(category) do
    # Get the current counters for this category
    counters = Process.get({:batch_logger, category}) || %{}

    # Skip if there are no events to flush
    if !Enum.empty?(counters) do
      # Log each group of events
      Enum.each(counters, fn {key, count} ->
        # Extract details from the key
        details = extract_details_from_key(key)

        # Format and log the batch
        log_batch(category, count, details)
      end)

      # Reset the counters for this category
      Process.put({:batch_logger, category}, %{})
    end

    :ok
  end

  # ------------------------------------------------------------
  # Private Helper Functions
  # ------------------------------------------------------------

  # Schedule the next periodic flush
  defp schedule_flush do
    Process.send_after(self(), :flush_batch_logs, @flush_interval)
  end

  # Handle the periodic flush message
  def handle_info(:flush_batch_logs, state) do
    # Flush all batched logs
    flush_all()

    # Schedule the next flush
    schedule_flush()

    {:noreply, state}
  end

  # Check if we should log now based on the current count
  defp should_log_now?(count) do
    # Log at powers of 10 (1, 10, 100, 1000, etc.)
    # Also log at every 1000 events after 1000
    count in [1, 10, 100, 1000, 10_000] ||
      (count > 1000 && rem(count, 1000) == 0)
  end

  # Create a unique key for an event based on its details
  defp create_event_key(details) do
    details
    |> Enum.sort_by(fn {k, _} -> to_string(k) end)
    |> Enum.map_join(":", fn {k, v} -> "#{k}=#{v}" end)
  end

  # Extract details from a key string
  defp extract_details_from_key(key) do
    key
    |> String.split(":")
    |> Enum.map(fn pair ->
      case String.split(pair, "=", parts: 2) do
        [k, v] -> {String.to_atom(k), v}
        _ -> {:unknown, pair}
      end
    end)
    |> Enum.into(%{})
  end

  # Log a batch of events
  defp log_batch(:kill_received, count, details) do
    system_info = Map.get(details, :system_id, "unknown")
    system_name = Map.get(details, :system_name, "")

    system_display =
      if system_name == "", do: system_info, else: "#{system_info} (#{system_name})"

    if count == 1 do
      # Single event, log normally with proper metadata
      AppLogger.kill_info(
        "📥 KILL RECEIVED: ID=#{Map.get(details, :kill_id, "unknown")} in system=#{system_display}",
        %{
          kill_id: Map.get(details, :kill_id, "unknown"),
          system_id: system_info,
          system_name: system_name
        }
      )
    else
      # Multiple events, log with counter and proper metadata
      AppLogger.kill_info(
        "📥 KILLS RECEIVED: #{count} kills in system=#{system_display}",
        %{
          count: count,
          system_id: system_info,
          system_name: system_name
        }
      )
    end
  end

  defp log_batch(:system_tracked, count, details) do
    system_info = Map.get(details, :system_id, "unknown")

    if count == 1 do
      # Single event, log at debug level
      AppLogger.processor_debug("System tracking check", system_id: system_info)
    else
      # Multiple events, log with counter at debug level
      AppLogger.processor_debug("System tracking batch", count: count, system_id: system_info)
    end
  end

  defp log_batch(:character_tracked, count, details) do
    if count == 1 do
      # Single event, log at debug level
      AppLogger.processor_debug("Character tracking check",
        character_id: Map.get(details, :character_id, "unknown")
      )
    else
      # Multiple events, log with counter
      AppLogger.processor_debug("Character tracking batch", count: count)
    end
  end

  defp log_batch(:cache_hit, count, details) do
    # Only log at debug level for cache operations
    AppLogger.cache_debug("Cache hits",
      count: count,
      key_pattern: Map.get(details, :key_pattern, "various")
    )
  end

  defp log_batch(:cache_miss, count, details) do
    # Only log at debug level for cache operations
    AppLogger.cache_debug("Cache misses",
      count: count,
      key_pattern: Map.get(details, :key_pattern, "various")
    )
  end

  defp log_batch(:notification_sent, count, details) do
    type = Map.get(details, :type, "unknown")

    if count == 1 do
      # Single notification
      AppLogger.processor_info("Notification sent",
        type: type,
        id: Map.get(details, :id, "unknown")
      )
    else
      # Multiple notifications
      AppLogger.processor_info("Notifications batch", count: count, type: type)
    end
  end

  defp log_batch(category, count, details) do
    # Generic handler for other categories
    AppLogger.processor_debug("#{category} events batch", count: count, details: inspect(details))
  end
end
