defmodule WandererNotifier.EventSourcing.Pipeline do
  @moduledoc """
  Event processing pipeline for the unified event sourcing system.

  Orchestrates the flow of events from various sources through validation,
  deduplication, enrichment, and processing stages.
  """

  use GenServer
  require Logger

  alias WandererNotifier.EventSourcing.{Event, Handlers}
  alias WandererNotifier.Infrastructure.Messaging.Deduplicator

  # Pipeline configuration
  @default_batch_size 100
  @default_batch_timeout 5_000
  @default_max_retries 3

  defmodule State do
    @moduledoc """
    Pipeline state structure.
    """

    defstruct [
      :batch_size,
      :batch_timeout,
      :max_retries,
      :current_batch,
      :batch_timer,
      :stats
    ]
  end

  @doc """
  Starts the event processing pipeline.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Processes a single event through the pipeline.
  """
  def process_event(%Event{} = event) do
    GenServer.cast(__MODULE__, {:process_event, event})
  end

  @doc """
  Processes multiple events in a batch.
  """
  def process_batch(events) when is_list(events) do
    GenServer.cast(__MODULE__, {:process_batch, events})
  end

  @doc """
  Gets pipeline statistics.
  """
  def get_stats do
    GenServer.call(__MODULE__, :get_stats)
  end

  @doc """
  Flushes the current batch immediately.
  """
  def flush_batch do
    GenServer.cast(__MODULE__, :flush_batch)
  end

  # Server Implementation

  @impl true
  def init(opts) do
    state = %State{
      batch_size: Keyword.get(opts, :batch_size, @default_batch_size),
      batch_timeout: Keyword.get(opts, :batch_timeout, @default_batch_timeout),
      max_retries: Keyword.get(opts, :max_retries, @default_max_retries),
      current_batch: [],
      batch_timer: nil,
      stats: %{
        events_processed: 0,
        events_failed: 0,
        batches_processed: 0,
        duplicates_filtered: 0,
        average_processing_time: 0.0,
        last_batch_time: nil
      }
    }

    Logger.info("Event processing pipeline started")
    {:ok, state}
  end

  @impl true
  def handle_cast({:process_event, event}, state) do
    # Add event to current batch
    new_batch = [event | state.current_batch]
    new_state = %{state | current_batch: new_batch}

    # Check if we should process the batch
    if length(new_batch) >= state.batch_size do
      process_current_batch(new_state)
    else
      # Set or reset the batch timer
      schedule_batch_processing(new_state)
    end
  end

  @impl true
  def handle_cast({:process_batch, events}, state) do
    # Process the batch immediately
    # Use prepending instead of appending for better performance
    batch_events = Enum.reduce(events, state.current_batch, fn event, acc -> [event | acc] end)
    process_batch_events(%{state | current_batch: batch_events})
  end

  @impl true
  def handle_cast(:flush_batch, state) do
    process_current_batch(state)
  end

  @impl true
  def handle_call(:get_stats, _from, state) do
    {:reply, state.stats, state}
  end

  @impl true
  def handle_info(:process_batch, state) do
    process_current_batch(state)
  end

  # Private functions

  defp process_current_batch(%State{current_batch: []} = state) do
    {:noreply, state}
  end

  defp process_current_batch(state) do
    process_batch_events(%{state | current_batch: Enum.reverse(state.current_batch)})
  end

  defp process_batch_events(%State{current_batch: batch} = state) when length(batch) > 0 do
    start_time = System.monotonic_time(:millisecond)

    Logger.debug("Processing batch of #{length(batch)} events")

    # Process the batch through the pipeline stages
    results =
      batch
      |> stage_validate_events()
      |> stage_deduplicate_events()
      |> stage_enrich_events()
      |> stage_process_events()

    end_time = System.monotonic_time(:millisecond)
    processing_time = end_time - start_time

    # Update statistics
    stats = update_batch_stats(state.stats, results, processing_time)

    Logger.info("Batch processed",
      batch_size: length(batch),
      processing_time_ms: processing_time,
      successes: results.successes,
      failures: results.failures,
      duplicates: results.duplicates
    )

    # Clear batch timer and reset state
    cancel_batch_timer(state.batch_timer)

    new_state = %{state | current_batch: [], batch_timer: nil, stats: stats}

    {:noreply, new_state}
  end

  defp process_batch_events(state) do
    {:noreply, state}
  end

  defp stage_validate_events(events) do
    {valid_events, invalid_events} =
      events
      |> Enum.split_with(fn event ->
        case Event.validate(event) do
          {:ok, _} -> true
          {:error, _} -> false
        end
      end)

    if length(invalid_events) > 0 do
      Logger.warning("#{length(invalid_events)} invalid events filtered out")
    end

    %{events: valid_events, invalid: length(invalid_events)}
  end

  defp stage_deduplicate_events(%{events: events} = result) do
    {unique_events, duplicates} =
      events
      |> Enum.split_with(fn event ->
        case Deduplicator.check_message(event) do
          {:ok, :processed} -> true
          {:ok, :duplicate} -> false
          # Include on error to avoid losing events
          {:error, _} -> true
        end
      end)

    if length(duplicates) > 0 do
      Logger.debug("#{length(duplicates)} duplicate events filtered out")
    end

    result
    |> Map.put(:events, unique_events)
    |> Map.put(:duplicates, length(duplicates))
  end

  defp stage_enrich_events(%{events: events} = result) do
    # Add enrichment metadata to events
    enriched_events =
      events
      |> Enum.map(fn event ->
        event
        |> Event.add_metadata(:pipeline_processed_at, System.monotonic_time(:millisecond))
        |> Event.add_metadata(:pipeline_stage, "enriched")
      end)

    Map.put(result, :events, enriched_events)
  end

  defp stage_process_events(%{events: events} = result) do
    # Process events through handlers
    processing_results = Handlers.handle_batch_events(events)

    # handle_batch_events always returns {:ok, _}
    {:ok, %{successes: successes, failures: failures}} = processing_results

    result
    |> Map.put(:successes, successes)
    |> Map.put(:failures, failures)
    |> Map.put(:processing_results, processing_results)
  end

  defp schedule_batch_processing(state) do
    # Cancel existing timer
    cancel_batch_timer(state.batch_timer)

    # Schedule new timer
    timer = Process.send_after(self(), :process_batch, state.batch_timeout)

    {:noreply, %{state | batch_timer: timer}}
  end

  defp cancel_batch_timer(nil), do: :ok

  defp cancel_batch_timer(timer) do
    Process.cancel_timer(timer)
    :ok
  end

  defp update_batch_stats(stats, results, processing_time) do
    successes = Map.get(results, :successes, 0)
    failures = Map.get(results, :failures, 0)
    duplicates = Map.get(results, :duplicates, 0)

    # Calculate rolling average processing time
    current_avg = stats.average_processing_time
    batches_count = stats.batches_processed + 1
    new_avg = (current_avg * stats.batches_processed + processing_time) / batches_count

    %{
      events_processed: stats.events_processed + successes,
      events_failed: stats.events_failed + failures,
      batches_processed: batches_count,
      duplicates_filtered: stats.duplicates_filtered + duplicates,
      average_processing_time: new_avg,
      last_batch_time: System.monotonic_time(:millisecond)
    }
  end
end
