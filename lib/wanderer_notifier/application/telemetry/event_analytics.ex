defmodule WandererNotifier.Application.Telemetry.Metrics.EventAnalytics do
  @moduledoc """
  Event analytics module for tracking and analyzing events from different sources.

  Provides detailed insights into event processing, source reliability,
  and data quality metrics across WebSocket, SSE, and HTTP sources.
  """

  use GenServer
  require Logger

  # Analytics configuration
  # 1 hour
  @default_window_size 3_600_000
  # 1 minute buckets
  @default_bucket_size 60_000

  defmodule State do
    @moduledoc """
    Event analytics state structure.
    """

    defstruct [
      :window_size,
      :bucket_size,
      :event_buckets,
      :source_metrics,
      :pattern_cache,
      :stats
    ]
  end

  @doc """
  Starts the event analytics service.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Records an event for analytics.
  """
  def record_event(event) do
    GenServer.cast(__MODULE__, {:record_event, event})
  end

  @doc """
  Gets event analytics by source.
  """
  def get_source_analytics do
    GenServer.call(__MODULE__, :get_source_analytics)
  end

  @doc """
  Gets event pattern analysis.
  """
  def get_pattern_analysis do
    GenServer.call(__MODULE__, :get_pattern_analysis)
  end

  @doc """
  Gets event distribution over time.
  """
  def get_event_distribution(time_range \\ :last_hour) do
    GenServer.call(__MODULE__, {:get_event_distribution, time_range})
  end

  @doc """
  Gets data quality metrics by source.
  """
  def get_quality_metrics do
    GenServer.call(__MODULE__, :get_quality_metrics)
  end

  # Server Implementation

  @impl true
  def init(opts) do
    window_size = Keyword.get(opts, :window_size, @default_window_size)
    bucket_size = Keyword.get(opts, :bucket_size, @default_bucket_size)

    state = %State{
      window_size: window_size,
      bucket_size: bucket_size,
      event_buckets: %{},
      source_metrics: %{
        websocket: init_source_metrics(),
        sse: init_source_metrics(),
        http: init_source_metrics(),
        internal: init_source_metrics()
      },
      pattern_cache: %{},
      stats: %{
        total_events_analyzed: 0,
        patterns_detected: 0,
        last_analysis_time: nil
      }
    }

    # Schedule periodic cleanup
    schedule_cleanup(window_size)

    Logger.info("Event analytics started", window_minutes: div(window_size, 60_000))

    {:ok, state}
  end

  @impl true
  def handle_cast({:record_event, event}, state) do
    new_state =
      state
      |> update_event_buckets(event)
      |> update_source_metrics(event)
      |> detect_patterns(event)
      |> update_stats()

    {:noreply, new_state}
  end

  @impl true
  def handle_call(:get_source_analytics, _from, state) do
    analytics = generate_source_analytics(state)
    {:reply, analytics, state}
  end

  @impl true
  def handle_call(:get_pattern_analysis, _from, state) do
    patterns = analyze_patterns(state)
    {:reply, patterns, state}
  end

  @impl true
  def handle_call({:get_event_distribution, time_range}, _from, state) do
    distribution = calculate_event_distribution(state, time_range)
    {:reply, distribution, state}
  end

  @impl true
  def handle_call(:get_quality_metrics, _from, state) do
    metrics = calculate_quality_metrics(state)
    {:reply, metrics, state}
  end

  @impl true
  def handle_info(:cleanup_old_data, state) do
    new_state = cleanup_old_buckets(state)
    schedule_cleanup(state.window_size)
    {:noreply, new_state}
  end

  # Private functions

  defp init_source_metrics do
    %{
      total_events: 0,
      successful_events: 0,
      failed_events: 0,
      average_latency: 0.0,
      latency_samples: [],
      error_types: %{},
      last_event_time: nil,
      uptime_percentage: 100.0,
      data_quality_score: 100.0
    }
  end

  defp update_event_buckets(state, event) do
    bucket_key = get_bucket_key(event.timestamp, state.bucket_size)
    source = event.source

    updated_buckets =
      Map.update(state.event_buckets, bucket_key, %{}, fn bucket ->
        Map.update(bucket, source, 1, &(&1 + 1))
      end)

    %{state | event_buckets: updated_buckets}
  end

  defp update_source_metrics(state, event) do
    source = event.source
    metrics = Map.get(state.source_metrics, source, init_source_metrics())

    # Calculate processing latency
    latency = calculate_event_latency(event)

    # Update metrics
    updated_metrics =
      metrics
      |> Map.update(:total_events, 1, &(&1 + 1))
      |> update_success_metrics(event)
      |> update_latency_metrics(latency)
      |> Map.put(:last_event_time, System.monotonic_time(:millisecond))
      |> update_quality_score(event)

    updated_source_metrics = Map.put(state.source_metrics, source, updated_metrics)

    %{state | source_metrics: updated_source_metrics}
  end

  defp detect_patterns(state, event) do
    # Simple pattern detection for bursts and anomalies
    case event.type do
      "killmail_received" ->
        update_pattern_cache(state, :killmail_burst, event)

      "system_updated" ->
        update_pattern_cache(state, :system_activity, event)

      "character_updated" ->
        update_pattern_cache(state, :character_movement, event)

      _ ->
        state
    end
  end

  defp update_pattern_cache(state, pattern_type, event) do
    key = {pattern_type, get_pattern_window(event.timestamp)}

    updated_cache =
      Map.update(state.pattern_cache, key, [event], fn events ->
        [event | Enum.take(events, 99)]
      end)

    %{state | pattern_cache: updated_cache}
  end

  defp generate_source_analytics(state) do
    Enum.map(state.source_metrics, fn {source, metrics} ->
      {source,
       %{
         total_events: metrics.total_events,
         success_rate: calculate_success_rate(metrics),
         average_latency: calculate_average_latency(metrics),
         uptime: metrics.uptime_percentage,
         data_quality: metrics.data_quality_score,
         last_seen: format_last_seen(metrics.last_event_time),
         error_distribution: metrics.error_types
       }}
    end)
    |> Map.new()
  end

  defp analyze_patterns(state) do
    current_time = System.monotonic_time(:millisecond)

    state.pattern_cache
    |> Enum.filter(fn {{_type, window}, _events} ->
      window > current_time - state.window_size
    end)
    |> Enum.map(fn {{type, _window}, events} ->
      %{
        pattern_type: type,
        event_count: length(events),
        # events per minute
        frequency: length(events) / (state.window_size / 1000 / 60),
        detected_at: List.first(events).timestamp
      }
    end)
    |> Enum.filter(fn pattern ->
      # Only report significant patterns
      pattern.frequency > 1.0
    end)
  end

  defp calculate_event_distribution(state, time_range) do
    {start_time, end_time} = get_time_range(time_range)

    state.event_buckets
    |> Enum.filter(fn {bucket_time, _data} ->
      bucket_time >= start_time and bucket_time <= end_time
    end)
    |> Enum.sort_by(&elem(&1, 0))
    |> Enum.map(fn {bucket_time, source_counts} ->
      %{
        timestamp: bucket_time,
        total: source_counts |> Map.values() |> Enum.sum(),
        by_source: source_counts
      }
    end)
  end

  defp calculate_quality_metrics(state) do
    Enum.map(state.source_metrics, fn {source, metrics} ->
      quality_factors = %{
        completeness: calculate_data_completeness(metrics),
        timeliness: calculate_timeliness_score(metrics),
        accuracy: calculate_accuracy_score(metrics),
        consistency: calculate_consistency_score(metrics)
      }

      overall_score =
        quality_factors.completeness * 0.3 +
          quality_factors.timeliness * 0.3 +
          quality_factors.accuracy * 0.2 +
          quality_factors.consistency * 0.2

      {source, Map.put(quality_factors, :overall_score, overall_score)}
    end)
    |> Map.new()
  end

  defp calculate_event_latency(%{metadata: %{received_at: received_at}} = event) do
    event.timestamp - received_at
  end

  defp calculate_event_latency(_event), do: 0

  defp update_success_metrics(metrics, %{metadata: %{processing_status: :success}}) do
    Map.update(metrics, :successful_events, 1, &(&1 + 1))
  end

  defp update_success_metrics(metrics, %{metadata: %{processing_status: :failed, error: error}}) do
    metrics
    |> Map.update(:failed_events, 1, &(&1 + 1))
    |> Map.update(:error_types, %{error => 1}, fn errors ->
      Map.update(errors, error, 1, &(&1 + 1))
    end)
  end

  defp update_success_metrics(metrics, _event) do
    Map.update(metrics, :successful_events, 1, &(&1 + 1))
  end

  defp update_latency_metrics(metrics, latency) do
    samples = [latency | Enum.take(metrics.latency_samples, 99)]
    avg_latency = Enum.sum(samples) / length(samples)

    metrics
    |> Map.put(:latency_samples, samples)
    |> Map.put(:average_latency, avg_latency)
  end

  defp update_quality_score(metrics, event) do
    # Simple quality scoring based on event completeness
    quality_score = calculate_event_quality(event)

    current_score = metrics.data_quality_score
    # Exponential smoothing
    new_score = current_score * 0.95 + quality_score * 0.05

    Map.put(metrics, :data_quality_score, new_score)
  end

  defp calculate_event_quality(%{data: data}) when is_map(data) do
    required_fields = get_required_fields_for_type(data)
    present_fields = Map.keys(data)

    if length(required_fields) > 0 do
      present_count = Enum.count(required_fields, &(&1 in present_fields))
      present_count / length(required_fields) * 100.0
    else
      100.0
    end
  end

  defp calculate_event_quality(_), do: 50.0

  defp get_required_fields_for_type(%{killmail_id: _}), do: [:killmail_id, :hash, :zkb]
  defp get_required_fields_for_type(%{system_id: _}), do: [:system_id, :event_type]
  defp get_required_fields_for_type(%{character_id: _}), do: [:character_id, :event]
  defp get_required_fields_for_type(_), do: []

  defp calculate_success_rate(%{total_events: 0}), do: 100.0

  defp calculate_success_rate(%{total_events: total, successful_events: successful}) do
    successful / total * 100.0
  end

  defp calculate_average_latency(%{latency_samples: []}), do: 0.0

  defp calculate_average_latency(%{latency_samples: samples}) do
    Enum.sum(samples) / length(samples)
  end

  defp calculate_data_completeness(metrics) do
    if metrics.total_events > 0 do
      metrics.successful_events / metrics.total_events * 100.0
    else
      0.0
    end
  end

  defp calculate_timeliness_score(%{average_latency: latency}) do
    cond do
      latency < 100 -> 100.0
      latency < 500 -> 90.0
      latency < 1000 -> 70.0
      latency < 5000 -> 50.0
      true -> 30.0
    end
  end

  defp calculate_accuracy_score(%{data_quality_score: score}), do: score

  defp calculate_consistency_score(%{total_events: total, failed_events: failed}) do
    if total > 0 do
      (1 - failed / total) * 100.0
    else
      100.0
    end
  end

  defp get_bucket_key(timestamp, bucket_size) do
    div(timestamp, bucket_size) * bucket_size
  end

  defp get_pattern_window(timestamp) do
    # 5-minute windows for pattern detection
    div(timestamp, 300_000) * 300_000
  end

  defp format_last_seen(nil), do: "never"

  defp format_last_seen(timestamp) do
    age_ms = System.monotonic_time(:millisecond) - timestamp

    cond do
      age_ms < 1000 -> "just now"
      age_ms < 60_000 -> "#{div(age_ms, 1000)}s ago"
      age_ms < 3_600_000 -> "#{div(age_ms, 60_000)}m ago"
      true -> "#{div(age_ms, 3_600_000)}h ago"
    end
  end

  defp get_time_range(:last_hour),
    do: {System.monotonic_time(:millisecond) - 3_600_000, System.monotonic_time(:millisecond)}

  defp get_time_range(:last_day),
    do: {System.monotonic_time(:millisecond) - 86_400_000, System.monotonic_time(:millisecond)}

  defp get_time_range({start_time, end_time}), do: {start_time, end_time}

  defp update_stats(state) do
    stats =
      Map.merge(state.stats, %{
        total_events_analyzed: state.stats.total_events_analyzed + 1,
        patterns_detected: map_size(state.pattern_cache),
        last_analysis_time: System.monotonic_time(:millisecond)
      })

    %{state | stats: stats}
  end

  defp cleanup_old_buckets(state) do
    cutoff_time = System.monotonic_time(:millisecond) - state.window_size

    cleaned_buckets =
      state.event_buckets
      |> Enum.filter(fn {bucket_time, _} -> bucket_time > cutoff_time end)
      |> Map.new()

    cleaned_patterns =
      state.pattern_cache
      |> Enum.filter(fn {{_type, window}, _} -> window > cutoff_time end)
      |> Map.new()

    %{state | event_buckets: cleaned_buckets, pattern_cache: cleaned_patterns}
  end

  defp schedule_cleanup(window_size) do
    # Cleanup every 10% of the window size
    Process.send_after(self(), :cleanup_old_data, div(window_size, 10))
  end
end
