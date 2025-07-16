defmodule WandererNotifier.Realtime.Deduplicator do
  @moduledoc """
  Message deduplication system for real-time sources.

  Supports cross-source deduplication between WebSocket and SSE connections
  with configurable strategies and automatic cleanup.
  """

  use GenServer
  require Logger

  alias WandererNotifier.Realtime.MessageTracker

  # Deduplication strategies
  @strategies [:hash_based, :content_based, :time_based, :hybrid]

  # Default configuration
  @default_strategy :hybrid
  # 5 minutes
  @default_ttl 300_000
  @default_hash_algorithm :sha256

  defmodule State do
    @moduledoc """
    Deduplicator state structure.
    """

    defstruct [
      :strategy,
      :ttl,
      :hash_algorithm,
      :stats
    ]
  end

  @doc """
  Starts the deduplicator GenServer.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Checks if a message is a duplicate and tracks it if it's new.
  Returns {:ok, :processed} for new messages or {:ok, :duplicate} for duplicates.
  """
  def check_message(message, opts \\ []) do
    GenServer.call(__MODULE__, {:check_message, message, opts})
  end

  @doc """
  Gets deduplication statistics.
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

  @doc """
  Updates the deduplication strategy.
  """
  def set_strategy(strategy) when strategy in @strategies do
    GenServer.cast(__MODULE__, {:set_strategy, strategy})
  end

  # Server Implementation

  @impl true
  def init(opts) do
    strategy = Keyword.get(opts, :strategy, @default_strategy)
    ttl = Keyword.get(opts, :ttl, @default_ttl)
    hash_algorithm = Keyword.get(opts, :hash_algorithm, @default_hash_algorithm)

    state = %State{
      strategy: strategy,
      ttl: ttl,
      hash_algorithm: hash_algorithm,
      stats: %{
        total_processed: 0,
        duplicates_found: 0,
        strategy_counts: %{}
      }
    }

    Logger.info("Message deduplicator started with strategy: #{strategy}")
    {:ok, state}
  end

  @impl true
  def handle_call({:check_message, message, opts}, _from, state) do
    strategy = Keyword.get(opts, :strategy, state.strategy)
    ttl = Keyword.get(opts, :ttl, state.ttl)

    # Generate deduplication key based on strategy
    key = generate_deduplication_key(message, strategy, state)

    # Check with message tracker
    is_duplicate = not MessageTracker.track_message(key, ttl)

    # Update statistics
    stats = update_deduplication_stats(state.stats, strategy, is_duplicate)
    new_state = %{state | stats: stats}

    result =
      if is_duplicate do
        Logger.debug("Duplicate message detected", strategy: strategy, key: inspect(key))
        {:ok, :duplicate}
      else
        Logger.debug("New message processed", strategy: strategy, key: inspect(key))
        {:ok, :processed}
      end

    {:reply, result, new_state}
  end

  @impl true
  def handle_call(:get_stats, _from, state) do
    # Combine our stats with MessageTracker stats
    tracker_stats = MessageTracker.get_stats()

    combined_stats =
      Map.merge(state.stats, %{
        tracker_stats: tracker_stats,
        current_strategy: state.strategy,
        ttl: state.ttl
      })

    {:reply, combined_stats, state}
  end

  @impl true
  def handle_cast({:set_strategy, strategy}, state) do
    Logger.info("Deduplication strategy changed from #{state.strategy} to #{strategy}")
    {:noreply, %{state | strategy: strategy}}
  end

  @impl true
  def handle_cast(:clear_all, state) do
    MessageTracker.clear_all()

    stats = %{
      total_processed: 0,
      duplicates_found: 0,
      strategy_counts: %{}
    }

    {:noreply, %{state | stats: stats}}
  end

  # Private functions

  defp generate_deduplication_key(message, strategy, state) do
    case strategy do
      :hash_based ->
        generate_hash_key(message, state.hash_algorithm)

      :content_based ->
        generate_content_key(message)

      :time_based ->
        generate_time_key(message)

      :hybrid ->
        generate_hybrid_key(message, state)
    end
  end

  defp generate_hash_key(message, algorithm) do
    # Create a hash of the entire message
    content = :erlang.term_to_binary(message)
    hash = :crypto.hash(algorithm, content)
    "hash:" <> Base.encode16(hash, case: :lower)
  end

  defp generate_content_key(message) do
    # Extract key content fields for deduplication
    key_fields = extract_key_fields(message)
    ("content:" <> :erlang.term_to_binary(key_fields)) |> Base.encode64()
  end

  defp generate_time_key(message) do
    # Use timestamp-based windowing
    # 30 seconds
    window_size = 30_000

    timestamp = extract_timestamp(message)
    window = div(timestamp, window_size) * window_size

    # Combine with basic content hash for uniqueness within window
    content_hash = generate_hash_key(message, :md5)
    "time:#{window}:#{content_hash}"
  end

  defp generate_hybrid_key(message, state) do
    # Combine multiple strategies for robust deduplication
    content_key = extract_key_fields(message)
    content_hash = :crypto.hash(state.hash_algorithm, :erlang.term_to_binary(content_key))

    # Use shorter time window for hybrid approach
    timestamp = extract_timestamp(message)
    # 10-second windows
    time_window = div(timestamp, 10_000) * 10_000

    source = Map.get(message, :source, "unknown")
    type = Map.get(message, :type, "unknown")

    "hybrid:#{source}:#{type}:#{time_window}:" <> Base.encode16(content_hash, case: :lower)
  end

  defp extract_key_fields(message) do
    # Extract the most important fields for deduplication
    case message do
      %{type: "killmail", data: %{killmail_id: id}} ->
        %{type: "killmail", id: id}

      %{type: "sse_event", data: %{event_type: event_type, system_id: system_id}} ->
        %{type: "sse_event", event_type: event_type, system_id: system_id}

      %{type: "character_event", data: %{character_id: char_id, event: event}} ->
        %{type: "character_event", character_id: char_id, event: event}

      %{id: id, type: type} when not is_nil(id) ->
        %{type: type, id: id}

      %{data: data, type: type} when is_map(data) ->
        # Extract ID-like fields from data
        id_fields = extract_id_fields(data)
        %{type: type, data: id_fields}

      _ ->
        # Fallback to entire message structure
        message
    end
  end

  defp extract_id_fields(data) when is_map(data) do
    # Common ID field patterns
    id_keys = [:id, :killmail_id, :character_id, :system_id, :event_id, :user_id]

    data
    |> Enum.filter(fn {key, _value} -> key in id_keys end)
    |> Map.new()
  end

  defp extract_timestamp(message) do
    case message do
      %{timestamp: ts} when is_integer(ts) -> ts
      %{data: %{timestamp: ts}} when is_integer(ts) -> ts
      %{received_at: ts} when is_integer(ts) -> ts
      _ -> System.monotonic_time(:millisecond)
    end
  end

  defp update_deduplication_stats(stats, strategy, is_duplicate) do
    updated_stats =
      stats
      |> Map.update(:total_processed, 1, &(&1 + 1))
      |> Map.update(:strategy_counts, %{}, fn counts ->
        Map.update(counts, strategy, 1, &(&1 + 1))
      end)

    if is_duplicate do
      Map.update(updated_stats, :duplicates_found, 1, &(&1 + 1))
    else
      updated_stats
    end
  end
end
