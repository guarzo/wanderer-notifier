defmodule WandererNotifier.Infrastructure.Messaging.MessageTracker do
  @moduledoc """
  Message tracking system using ETS for fast in-memory storage.

  Provides sliding window cache for message deduplication with configurable TTLs
  and automatic cleanup of expired entries.
  """

  use GenServer
  require Logger

  # Default configuration
  # 5 minutes in milliseconds
  @default_ttl 300_000
  @default_max_size 5_000
  # 1 minute
  @cleanup_interval 60_000

  @doc """
  Starts the message tracker GenServer.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Tracks a message with a given key and optional TTL.
  Returns true if message is new, false if it's a duplicate.
  """
  def track_message(key, ttl \\ @default_ttl) do
    GenServer.call(__MODULE__, {:track_message, key, ttl})
  end

  @doc """
  Checks if a message has been seen before without tracking it.
  """
  def has_message?(key) do
    GenServer.call(__MODULE__, {:has_message, key})
  end

  @doc """
  Removes a message from tracking.
  """
  def remove_message(key) do
    GenServer.cast(__MODULE__, {:remove_message, key})
  end

  @doc """
  Gets the current cache statistics.
  """
  def get_stats do
    GenServer.call(__MODULE__, :get_stats)
  end

  @doc """
  Clears all tracked messages.
  """
  def clear_all do
    GenServer.cast(__MODULE__, :clear_all)
  end

  # Server Implementation

  @impl true
  def init(opts) do
    # Create ETS tables for different tracking strategies
    hash_table = :ets.new(:message_hash_tracker, [:set, :protected, :named_table])
    content_table = :ets.new(:message_content_tracker, [:set, :protected, :named_table])
    time_table = :ets.new(:message_time_tracker, [:ordered_set, :protected, :named_table])
    expiry_index = :ets.new(:message_expiry_index, [:ordered_set, :protected, :named_table])

    # Schedule periodic cleanup
    schedule_cleanup()

    state = %{
      hash_table: hash_table,
      content_table: content_table,
      time_table: time_table,
      expiry_index: expiry_index,
      max_size: Keyword.get(opts, :max_size, @default_max_size),
      stats: %{
        total_messages: 0,
        duplicates_found: 0,
        cache_hits: 0,
        cache_misses: 0,
        evictions: 0,
        memory_usage: 0
      }
    }

    Logger.info("Message tracker started")
    {:ok, state}
  end

  @impl true
  def handle_call({:track_message, key, ttl}, _from, state) do
    now = System.monotonic_time(:millisecond)
    expiry_time = now + ttl

    # Check if we already have this message
    case :ets.lookup(state.hash_table, key) do
      [] ->
        # New message - track it
        :ets.insert(state.hash_table, {key, now, expiry_time})
        :ets.insert(state.expiry_index, {expiry_time, key})

        # Update stats
        stats = update_stats(state.stats, :new_message)
        new_state = %{state | stats: stats}

        # Check if we need to evict old entries
        final_state = maybe_evict_oldest(new_state)

        {:reply, true, final_state}

      [{^key, _timestamp, _expiry}] ->
        # Duplicate message
        stats = update_stats(state.stats, :duplicate)
        {:reply, false, %{state | stats: stats}}
    end
  end

  @impl true
  def handle_call({:has_message, key}, _from, state) do
    result =
      case :ets.lookup(state.hash_table, key) do
        [] ->
          stats = update_stats(state.stats, :cache_miss)
          {false, %{state | stats: stats}}

        [{^key, _timestamp, expiry_time}] ->
          now = System.monotonic_time(:millisecond)

          if now < expiry_time do
            stats = update_stats(state.stats, :cache_hit)
            {true, %{state | stats: stats}}
          else
            # Expired - remove it
            :ets.delete(state.hash_table, key)
            :ets.delete(state.expiry_index, expiry_time)
            stats = update_stats(state.stats, :cache_miss)
            {false, %{state | stats: stats}}
          end
      end

    case result do
      {reply, new_state} -> {:reply, reply, new_state}
    end
  end

  @impl true
  def handle_call(:get_stats, _from, state) do
    # Update memory usage
    memory_info = :ets.info(state.hash_table, :memory) || 0

    updated_stats =
      Map.put(state.stats, :memory_usage, memory_info * :erlang.system_info(:wordsize))

    {:reply, updated_stats, %{state | stats: updated_stats}}
  end

  @impl true
  def handle_cast({:remove_message, key}, state) do
    case :ets.lookup(state.hash_table, key) do
      [{^key, _timestamp, expiry_time}] ->
        :ets.delete(state.hash_table, key)
        :ets.delete(state.expiry_index, expiry_time)
        {:noreply, state}

      [] ->
        {:noreply, state}
    end
  end

  @impl true
  def handle_cast(:clear_all, state) do
    :ets.delete_all_objects(state.hash_table)
    :ets.delete_all_objects(state.content_table)
    :ets.delete_all_objects(state.time_table)
    :ets.delete_all_objects(state.expiry_index)

    stats = %{
      total_messages: 0,
      duplicates_found: 0,
      cache_hits: 0,
      cache_misses: 0,
      evictions: 0,
      memory_usage: 0
    }

    {:noreply, %{state | stats: stats}}
  end

  @impl true
  def handle_info(:cleanup, state) do
    # Clean up expired entries
    now = System.monotonic_time(:millisecond)
    new_state = cleanup_expired_entries(state, now)

    # Schedule next cleanup
    schedule_cleanup()

    {:noreply, new_state}
  end

  # Private functions

  defp schedule_cleanup do
    Process.send_after(self(), :cleanup, @cleanup_interval)
  end

  defp update_stats(stats, event) do
    case event do
      :new_message -> increment_new_message_stats(stats)
      :duplicate -> increment_duplicate_stats(stats)
      :cache_hit -> increment_stat(stats, :cache_hits)
      :cache_miss -> increment_stat(stats, :cache_misses)
      :eviction -> increment_stat(stats, :evictions)
    end
  end

  defp increment_new_message_stats(stats) do
    stats
    |> increment_stat(:total_messages)
    |> increment_stat(:cache_misses)
  end

  defp increment_duplicate_stats(stats) do
    stats
    |> increment_stat(:duplicates_found)
    |> increment_stat(:cache_hits)
  end

  defp increment_stat(stats, key) do
    Map.update(stats, key, 1, &(&1 + 1))
  end

  defp maybe_evict_oldest(state) do
    table_size = :ets.info(state.hash_table, :size) || 0

    if table_size > state.max_size do
      evict_oldest_entries(state, table_size - state.max_size)
    else
      state
    end
  end

  defp evict_oldest_entries(state, count) when count > 0 do
    # Find the oldest entries by expiry time
    case :ets.first(state.expiry_index) do
      :"$end_of_table" ->
        state

      expiry_time ->
        case :ets.lookup(state.expiry_index, expiry_time) do
          [{^expiry_time, key}] ->
            # Remove from both tables
            :ets.delete(state.hash_table, key)
            :ets.delete(state.expiry_index, expiry_time)

            # Update stats and continue
            stats = update_stats(state.stats, :eviction)
            new_state = %{state | stats: stats}
            evict_oldest_entries(new_state, count - 1)

          [] ->
            # Entry already removed, continue with next
            evict_oldest_entries(state, count)
        end
    end
  end

  defp evict_oldest_entries(state, 0), do: state

  defp cleanup_expired_entries(state, now) do
    # Walk through expiry index and remove expired entries
    cleanup_expired_entries(state, now, :ets.first(state.expiry_index), 0)
  end

  defp cleanup_expired_entries(state, _now, :"$end_of_table", cleaned_count) do
    if cleaned_count > 0 do
      Logger.debug("Cleaned up #{cleaned_count} expired message entries")
    end

    state
  end

  defp cleanup_expired_entries(state, now, expiry_time, cleaned_count) when expiry_time <= now do
    # This entry has expired
    case :ets.lookup(state.expiry_index, expiry_time) do
      [{^expiry_time, key}] ->
        :ets.delete(state.hash_table, key)
        :ets.delete(state.expiry_index, expiry_time)

        # Continue with next entry
        next_key = :ets.next(state.expiry_index, expiry_time)
        cleanup_expired_entries(state, now, next_key, cleaned_count + 1)

      [] ->
        # Entry already removed, continue
        next_key = :ets.next(state.expiry_index, expiry_time)
        cleanup_expired_entries(state, now, next_key, cleaned_count)
    end
  end

  defp cleanup_expired_entries(state, _now, _expiry_time, cleaned_count) do
    # All remaining entries are not yet expired (ordered_set guarantees this)
    if cleaned_count > 0 do
      Logger.debug("Cleaned up #{cleaned_count} expired message entries")
    end

    state
  end
end
