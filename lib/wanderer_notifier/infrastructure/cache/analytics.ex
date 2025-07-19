defmodule WandererNotifier.Infrastructure.Cache.Analytics do
  @moduledoc """
  Cache usage analytics collection and reporting system.

  This module provides comprehensive analytics collection for cache usage patterns,
  performance metrics, and efficiency analysis. It integrates with the existing
  cache metrics and performance monitoring systems to provide detailed insights.

  ## Features

  - Real-time cache usage pattern analysis
  - Key access frequency tracking
  - Cache efficiency metrics calculation
  - Performance trend analysis
  - Memory usage patterns
  - Hit/miss ratio analysis by data type
  - Time-based usage analytics
  - Cache hotspot identification

  ## Usage

  ```elixir
  # Start analytics collection
  WandererNotifier.Infrastructure.Cache.Analytics.start_collection()

  # Get usage report
  report = WandererNotifier.Infrastructure.Cache.Analytics.get_usage_report()

  # Get efficiency metrics
  metrics = WandererNotifier.Infrastructure.Cache.Analytics.get_efficiency_metrics()

  # Analyze cache patterns
  patterns = WandererNotifier.Infrastructure.Cache.Analytics.analyze_patterns()
  ```
  """

  use GenServer
  require Logger

  alias WandererNotifier.Infrastructure.Cache.Metrics
  alias WandererNotifier.Infrastructure.Cache.PerformanceMonitor

  @type usage_stats :: %{
          total_operations: integer(),
          hit_count: integer(),
          miss_count: integer(),
          hit_rate: float(),
          miss_rate: float(),
          average_response_time: float(),
          peak_usage_time: DateTime.t() | nil,
          data_type_breakdown: map()
        }

  @type efficiency_metrics :: %{
          overall_efficiency: float(),
          memory_efficiency: float(),
          time_efficiency: float(),
          cache_utilization: float(),
          optimization_score: float()
        }

  @type pattern_analysis :: %{
          hotspots: [String.t()],
          cold_keys: [String.t()],
          usage_patterns: map(),
          temporal_patterns: map(),
          recommendations: [String.t()]
        }

  # Collection intervals
  # 1 minute
  @collection_interval 60_000
  # 24 hours
  @retention_period 24 * 60 * 60 * 1000

  # Analytics configuration
  @default_config %{
    collection_enabled: true,
    retention_period: @retention_period,
    collection_interval: @collection_interval,
    max_hotspots: 50,
    max_cold_keys: 100,
    efficiency_threshold: 0.8,
    memory_threshold: 0.9
  }

  @doc """
  Starts the cache analytics GenServer.

  ## Options
  - `:name` - Name for the GenServer (default: __MODULE__)
  - All options from @default_config can be overridden
  """
  def start_link(opts \\ []) do
    {name, opts} = Keyword.pop(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Starts cache analytics collection.

  ## Returns
  :ok
  """
  @spec start_collection() :: :ok
  def start_collection do
    GenServer.call(__MODULE__, :start_collection)
  end

  @doc """
  Stops cache analytics collection.

  ## Returns
  :ok
  """
  @spec stop_collection() :: :ok
  def stop_collection do
    GenServer.call(__MODULE__, :stop_collection)
  end

  @doc """
  Gets comprehensive usage report.

  ## Returns
  Usage statistics map
  """
  @spec get_usage_report() :: usage_stats()
  def get_usage_report do
    GenServer.call(__MODULE__, :get_usage_report)
  end

  @doc """
  Gets cache efficiency metrics.

  ## Returns
  Efficiency metrics map
  """
  @spec get_efficiency_metrics() :: efficiency_metrics()
  def get_efficiency_metrics do
    GenServer.call(__MODULE__, :get_efficiency_metrics)
  end

  @doc """
  Analyzes cache usage patterns.

  ## Returns
  Pattern analysis map
  """
  @spec analyze_patterns() :: pattern_analysis()
  def analyze_patterns do
    GenServer.call(__MODULE__, :analyze_patterns)
  end

  @doc """
  Gets historical analytics data.

  ## Parameters
  - time_range: Time range in milliseconds from now

  ## Returns
  Historical analytics data
  """
  @spec get_historical_data(integer()) :: map()
  def get_historical_data(time_range \\ @retention_period) do
    GenServer.call(__MODULE__, {:get_historical_data, time_range})
  end

  @doc """
  Records a cache operation for analytics.

  ## Parameters
  - operation: Operation type (:get, :put, :delete, etc.)
  - key: Cache key
  - result: Operation result (:hit, :miss, :ok, etc.)
  - duration: Operation duration in milliseconds
  - metadata: Additional metadata

  ## Returns
  :ok
  """
  @spec record_operation(atom(), String.t(), atom(), integer(), map()) :: :ok
  def record_operation(operation, key, result, duration, metadata \\ %{}) do
    GenServer.cast(__MODULE__, {:record_operation, operation, key, result, duration, metadata})
  end

  @doc """
  Gets current analytics status.

  ## Returns
  Status map
  """
  @spec get_status() :: map()
  def get_status do
    GenServer.call(__MODULE__, :get_status)
  end

  @doc """
  Resets analytics data.

  ## Returns
  :ok
  """
  @spec reset_analytics() :: :ok
  def reset_analytics do
    GenServer.call(__MODULE__, :reset_analytics)
  end

  # GenServer callbacks

  @impl GenServer
  def init(opts) do
    config = Map.merge(@default_config, Map.new(opts))

    state = %{
      config: config,
      collection_active: false,
      operations: [],
      key_stats: %{},
      time_series: [],
      last_collection: nil,
      total_operations: 0,
      hit_count: 0,
      miss_count: 0,
      response_times: [],
      data_type_stats: %{}
    }

    Logger.info("Cache analytics initialized")
    {:ok, state}
  end

  @impl GenServer
  def handle_call(:start_collection, _from, state) do
    if state.collection_active do
      {:reply, :ok, state}
    else
      schedule_collection(state.config.collection_interval)
      new_state = %{state | collection_active: true}
      Logger.info("Cache analytics collection started")
      {:reply, :ok, new_state}
    end
  end

  @impl GenServer
  def handle_call(:stop_collection, _from, state) do
    new_state = %{state | collection_active: false}
    Logger.info("Cache analytics collection stopped")
    {:reply, :ok, new_state}
  end

  @impl GenServer
  def handle_call(:get_usage_report, _from, state) do
    report = build_usage_report(state)
    {:reply, report, state}
  end

  @impl GenServer
  def handle_call(:get_efficiency_metrics, _from, state) do
    metrics = calculate_efficiency_metrics(state)
    {:reply, metrics, state}
  end

  @impl GenServer
  def handle_call(:analyze_patterns, _from, state) do
    patterns = analyze_usage_patterns(state)
    {:reply, patterns, state}
  end

  @impl GenServer
  def handle_call({:get_historical_data, time_range}, _from, state) do
    historical_data = get_historical_analytics(state, time_range)
    {:reply, historical_data, state}
  end

  @impl GenServer
  def handle_call(:get_status, _from, state) do
    status = build_status_response(state)
    {:reply, status, state}
  end

  @impl GenServer
  def handle_call(:reset_analytics, _from, state) do
    reset_state = %{
      state
      | operations: [],
        key_stats: %{},
        time_series: [],
        total_operations: 0,
        hit_count: 0,
        miss_count: 0,
        response_times: [],
        data_type_stats: %{}
    }

    Logger.info("Cache analytics data reset")
    {:reply, :ok, reset_state}
  end

  @impl GenServer
  def handle_cast({:record_operation, operation, key, result, duration, metadata}, state) do
    if state.collection_active do
      new_state = record_operation_data(state, operation, key, result, duration, metadata)
      {:noreply, new_state}
    else
      {:noreply, state}
    end
  end

  @impl GenServer
  def handle_info(:collect_analytics, state) do
    if state.collection_active do
      new_state = collect_current_metrics(state)

      # Clean up old data
      cleaned_state = cleanup_old_data(new_state)

      # Schedule next collection
      schedule_collection(state.config.collection_interval)

      {:noreply, cleaned_state}
    else
      {:noreply, state}
    end
  end

  # Private functions

  defp schedule_collection(interval) do
    Process.send_after(self(), :collect_analytics, interval)
  end

  defp record_operation_data(state, operation, key, result, duration, metadata) do
    now = System.monotonic_time(:millisecond)

    operation_record = %{
      operation: operation,
      key: key,
      result: result,
      duration: duration,
      metadata: metadata,
      timestamp: now
    }

    # Update key statistics
    key_stats = update_key_stats(state.key_stats, key, result, duration)

    # Update data type statistics
    data_type = extract_data_type(key, metadata)
    data_type_stats = update_data_type_stats(state.data_type_stats, data_type, result)

    # Update counters
    {hit_count, miss_count} = update_counters(state.hit_count, state.miss_count, result)

    # Update response times (keep last 100 for moving averages to reduce memory)
    response_times =
      [duration | state.response_times]
      |> Enum.take(100)

    # Limit operations to 100 to reduce memory usage (was previously unbounded)
    limited_operations = [operation_record | state.operations] |> Enum.take(100)

    # Clean up old key stats (keep only last 500 accessed keys)
    cleaned_key_stats = cleanup_old_key_stats(key_stats)

    %{
      state
      | operations: limited_operations,
        key_stats: cleaned_key_stats,
        data_type_stats: data_type_stats,
        total_operations: state.total_operations + 1,
        hit_count: hit_count,
        miss_count: miss_count,
        response_times: response_times
    }
  end

  defp update_key_stats(key_stats, key, result, duration) do
    current_stats =
      Map.get(key_stats, key, %{
        access_count: 0,
        hit_count: 0,
        miss_count: 0,
        total_duration: 0,
        last_accessed: nil
      })

    new_stats = %{
      access_count: current_stats.access_count + 1,
      hit_count: current_stats.hit_count + if(result == :hit, do: 1, else: 0),
      miss_count: current_stats.miss_count + if(result == :miss, do: 1, else: 0),
      total_duration: current_stats.total_duration + duration,
      last_accessed: System.monotonic_time(:millisecond)
    }

    Map.put(key_stats, key, new_stats)
  end

  defp cleanup_old_key_stats(key_stats) do
    # If we have more than 100 keys, keep only the 100 most recently accessed
    if map_size(key_stats) > 100 do
      key_stats
      |> Enum.sort_by(fn {_key, stats} -> stats.last_accessed end, :desc)
      |> Enum.take(100)
      |> Map.new()
    else
      key_stats
    end
  end

  defp update_data_type_stats(data_type_stats, data_type, result) do
    current_stats =
      Map.get(data_type_stats, data_type, %{
        total_operations: 0,
        hit_count: 0,
        miss_count: 0
      })

    new_stats = %{
      total_operations: current_stats.total_operations + 1,
      hit_count: current_stats.hit_count + if(result == :hit, do: 1, else: 0),
      miss_count: current_stats.miss_count + if(result == :miss, do: 1, else: 0)
    }

    Map.put(data_type_stats, data_type, new_stats)
  end

  defp update_counters(hit_count, miss_count, result) do
    case result do
      :hit -> {hit_count + 1, miss_count}
      :miss -> {hit_count, miss_count + 1}
      _ -> {hit_count, miss_count}
    end
  end

  defp extract_data_type(key, metadata) do
    cond do
      String.contains?(key, ":character:") -> :character
      String.contains?(key, ":corporation:") -> :corporation
      String.contains?(key, ":alliance:") -> :alliance
      String.contains?(key, ":system:") -> :system
      Map.has_key?(metadata, :data_type) -> metadata.data_type
      true -> :unknown
    end
  end

  defp collect_current_metrics(state) do
    now = System.monotonic_time(:millisecond)

    # Get current metrics from the metrics module
    current_metrics = get_current_metrics()

    # Get performance status
    performance_status = get_performance_status()

    time_series_entry = %{
      timestamp: now,
      metrics: current_metrics,
      performance: performance_status,
      operations_count: state.total_operations,
      hit_rate: calculate_hit_rate(state.hit_count, state.miss_count),
      avg_response_time: calculate_average_response_time(state.response_times)
    }

    # 24 hours but limit to 288 entries (5-minute intervals) to reduce memory usage
    new_time_series = [time_series_entry | state.time_series] |> Enum.take(288)

    %{state | time_series: new_time_series, last_collection: now}
  end

  defp cleanup_old_data(state) do
    now = System.monotonic_time(:millisecond)
    cutoff_time = now - state.config.retention_period

    # Clean up old operations
    recent_operations =
      Enum.filter(state.operations, fn op ->
        op.timestamp > cutoff_time
      end)

    # Clean up old time series data
    recent_time_series =
      Enum.filter(state.time_series, fn entry ->
        entry.timestamp > cutoff_time
      end)

    %{state | operations: recent_operations, time_series: recent_time_series}
  end

  defp build_usage_report(state) do
    hit_rate = calculate_hit_rate(state.hit_count, state.miss_count)
    miss_rate = 1.0 - hit_rate
    avg_response_time = calculate_average_response_time(state.response_times)

    peak_usage_time = find_peak_usage_time(state.time_series)

    data_type_breakdown = build_data_type_breakdown(state.data_type_stats)

    %{
      total_operations: state.total_operations,
      hit_count: state.hit_count,
      miss_count: state.miss_count,
      hit_rate: hit_rate,
      miss_rate: miss_rate,
      average_response_time: avg_response_time,
      peak_usage_time: peak_usage_time,
      data_type_breakdown: data_type_breakdown
    }
  end

  defp calculate_efficiency_metrics(state) do
    hit_rate = calculate_hit_rate(state.hit_count, state.miss_count)

    # Calculate memory efficiency (simplified)
    memory_efficiency = calculate_memory_efficiency(state.key_stats)

    # Calculate time efficiency based on response times
    time_efficiency = calculate_time_efficiency(state.response_times)

    # Calculate cache utilization
    cache_utilization = calculate_cache_utilization(state.key_stats)

    # Calculate overall optimization score
    optimization_score = (hit_rate + memory_efficiency + time_efficiency + cache_utilization) / 4

    %{
      overall_efficiency: hit_rate,
      memory_efficiency: memory_efficiency,
      time_efficiency: time_efficiency,
      cache_utilization: cache_utilization,
      optimization_score: optimization_score
    }
  end

  defp analyze_usage_patterns(state) do
    # Identify hotspots (frequently accessed keys)
    hotspots = identify_hotspots(state.key_stats, state.config.max_hotspots)

    # Identify cold keys (rarely accessed)
    cold_keys = identify_cold_keys(state.key_stats, state.config.max_cold_keys)

    # Analyze usage patterns
    usage_patterns = analyze_key_usage_patterns(state.key_stats)

    # Analyze temporal patterns
    temporal_patterns = analyze_temporal_patterns(state.time_series)

    # Generate recommendations
    recommendations = generate_recommendations(state)

    %{
      hotspots: hotspots,
      cold_keys: cold_keys,
      usage_patterns: usage_patterns,
      temporal_patterns: temporal_patterns,
      recommendations: recommendations
    }
  end

  defp get_historical_analytics(state, time_range) do
    cutoff_time = System.monotonic_time(:millisecond) - time_range

    historical_data =
      Enum.filter(state.time_series, fn entry ->
        entry.timestamp > cutoff_time
      end)

    %{
      time_range: time_range,
      data_points: length(historical_data),
      historical_data: historical_data
    }
  end

  defp build_status_response(state) do
    %{
      collection_active: state.collection_active,
      total_operations: state.total_operations,
      operations_buffer_size: length(state.operations),
      time_series_size: length(state.time_series),
      tracked_keys: map_size(state.key_stats),
      data_types: map_size(state.data_type_stats),
      last_collection: state.last_collection,
      config: state.config
    }
  end

  defp calculate_hit_rate(hit_count, miss_count) do
    total = hit_count + miss_count
    if total > 0, do: hit_count / total, else: 0.0
  end

  defp calculate_average_response_time(response_times) do
    if length(response_times) > 0 do
      Enum.sum(response_times) / length(response_times)
    else
      0.0
    end
  end

  defp find_peak_usage_time(time_series) do
    time_series
    |> Enum.max_by(& &1.operations_count, fn -> nil end)
    |> case do
      nil -> nil
      entry -> DateTime.from_unix!(entry.timestamp, :millisecond)
    end
  end

  defp build_data_type_breakdown(data_type_stats) do
    Enum.into(data_type_stats, %{}, fn {type, stats} ->
      hit_rate = calculate_hit_rate(stats.hit_count, stats.miss_count)
      {type, Map.put(stats, :hit_rate, hit_rate)}
    end)
  end

  defp calculate_memory_efficiency(key_stats) do
    # Simplified memory efficiency calculation
    # In a real implementation, this would analyze memory usage patterns
    total_keys = map_size(key_stats)
    if total_keys > 0, do: 0.8, else: 1.0
  end

  defp calculate_time_efficiency(response_times) do
    if length(response_times) > 0 do
      avg_time = calculate_average_response_time(response_times)
      # Assume 10ms is optimal response time
      optimal_time = 10.0
      max(0.0, min(1.0, optimal_time / avg_time))
    else
      1.0
    end
  end

  defp calculate_cache_utilization(key_stats) do
    # Simplified utilization calculation
    # In a real implementation, this would analyze cache size vs usage
    active_keys =
      Enum.count(key_stats, fn {_key, stats} ->
        stats.access_count > 0
      end)

    total_keys = map_size(key_stats)
    if total_keys > 0, do: active_keys / total_keys, else: 0.0
  end

  defp identify_hotspots(key_stats, max_hotspots) do
    key_stats
    |> Enum.sort_by(fn {_key, stats} -> stats.access_count end, :desc)
    |> Enum.take(max_hotspots)
    |> Enum.map(fn {key, _stats} -> key end)
  end

  defp identify_cold_keys(key_stats, max_cold_keys) do
    now = System.monotonic_time(:millisecond)
    one_hour_ago = now - 3_600_000

    key_stats
    |> Enum.filter(fn {_key, stats} ->
      stats.last_accessed && stats.last_accessed < one_hour_ago
    end)
    |> Enum.sort_by(fn {_key, stats} -> stats.access_count end, :asc)
    |> Enum.take(max_cold_keys)
    |> Enum.map(fn {key, _stats} -> key end)
  end

  defp analyze_key_usage_patterns(key_stats) do
    total_keys = map_size(key_stats)

    if total_keys > 0 do
      access_counts = Enum.map(key_stats, fn {_key, stats} -> stats.access_count end)

      %{
        total_keys: total_keys,
        average_access_count: Enum.sum(access_counts) / total_keys,
        max_access_count: Enum.max(access_counts),
        min_access_count: Enum.min(access_counts)
      }
    else
      %{
        total_keys: 0,
        average_access_count: 0.0,
        max_access_count: 0,
        min_access_count: 0
      }
    end
  end

  defp analyze_temporal_patterns(time_series) do
    if length(time_series) > 0 do
      # Group by hour of day
      hourly_patterns =
        time_series
        |> Enum.group_by(fn entry ->
          DateTime.from_unix!(entry.timestamp, :millisecond).hour
        end)
        |> Enum.into(%{}, fn {hour, entries} ->
          avg_operations =
            entries
            |> Enum.map(& &1.operations_count)
            |> Enum.sum()
            |> Kernel./(length(entries))

          {hour, avg_operations}
        end)

      %{
        hourly_patterns: hourly_patterns,
        peak_hour: Enum.max_by(hourly_patterns, fn {_hour, ops} -> ops end, fn -> {0, 0} end)
      }
    else
      %{hourly_patterns: %{}, peak_hour: {0, 0}}
    end
  end

  defp generate_recommendations(state) do
    recommendations = []

    # Memory recommendations
    recommendations =
      if map_size(state.key_stats) > 10_000 do
        [
          "Consider implementing cache size limits and eviction policies" | recommendations
        ]
      else
        recommendations
      end

    # Performance recommendations
    avg_response_time = calculate_average_response_time(state.response_times)

    recommendations =
      if avg_response_time > 50.0 do
        [
          "Average response time is high - consider cache optimization" | recommendations
        ]
      else
        recommendations
      end

    # Pattern-based recommendations
    cold_keys = identify_cold_keys(state.key_stats, 10)

    recommendations =
      if length(cold_keys) > 5 do
        ["Consider implementing TTL for rarely accessed keys" | recommendations]
      else
        recommendations
      end

    recommendations
  end

  defp get_current_metrics do
    try do
      Metrics.get_metrics()
    rescue
      _ -> %{}
    end
  end

  defp get_performance_status do
    try do
      PerformanceMonitor.get_status()
    rescue
      _ -> %{}
    end
  end
end
