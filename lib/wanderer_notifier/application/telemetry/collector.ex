defmodule WandererNotifier.Application.Telemetry.Metrics.Collector do
  @moduledoc """
  Metrics collection system for real-time performance monitoring.

  Collects and aggregates performance metrics from various components
  including connection health, message processing, and system resource usage.
  """

  use GenServer
  require Logger

  alias WandererNotifier.Infrastructure.Messaging.{ConnectionMonitor, Deduplicator}
  alias WandererNotifier.EventSourcing.Pipeline

  # Collection intervals
  # 30 seconds
  @default_collection_interval 30_000
  # 24 hours
  @default_retention_period 86_400_000
  # 5 minutes
  @default_aggregation_window 300_000

  defmodule State do
    @moduledoc """
    Collector state structure.
    """

    defstruct [
      :collection_interval,
      :retention_period,
      :aggregation_window,
      :metrics_history,
      :current_metrics,
      :collection_timer,
      :stats
    ]
  end

  defmodule Metrics do
    @moduledoc """
    Metrics data structure.
    """

    defstruct [
      :timestamp,
      :connection_metrics,
      :processing_metrics,
      :deduplication_metrics,
      :system_metrics,
      :performance_score
    ]
  end

  @doc """
  Starts the metrics collector.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Gets the latest collected metrics.
  """
  def get_current_metrics do
    GenServer.call(__MODULE__, :get_current_metrics)
  end

  @doc """
  Gets metrics history within a time range.
  """
  def get_metrics_history(start_time, end_time) do
    GenServer.call(__MODULE__, {:get_metrics_history, start_time, end_time})
  end

  @doc """
  Gets aggregated metrics for a specific time window.
  """
  def get_aggregated_metrics(window_size \\ nil) do
    GenServer.call(__MODULE__, {:get_aggregated_metrics, window_size})
  end

  @doc """
  Forces immediate metrics collection.
  """
  def collect_now do
    GenServer.cast(__MODULE__, :collect_now)
  end

  @doc """
  Gets collector statistics.
  """
  def get_stats do
    GenServer.call(__MODULE__, :get_stats)
  end

  # Server Implementation

  @impl true
  def init(opts) do
    collection_interval = Keyword.get(opts, :collection_interval, @default_collection_interval)
    retention_period = Keyword.get(opts, :retention_period, @default_retention_period)
    aggregation_window = Keyword.get(opts, :aggregation_window, @default_aggregation_window)

    state = %State{
      collection_interval: collection_interval,
      retention_period: retention_period,
      aggregation_window: aggregation_window,
      metrics_history: [],
      current_metrics: nil,
      collection_timer: nil,
      stats: %{
        collections_performed: 0,
        last_collection_time: nil,
        collection_errors: 0,
        memory_usage: 0
      }
    }

    # Start collection timer
    schedule_collection(state)

    Logger.info("Metrics collector started",
      interval_seconds: div(collection_interval, 1000),
      retention_hours: div(retention_period, 3_600_000)
    )

    {:ok, state}
  end

  @impl true
  def handle_call(:get_current_metrics, _from, state) do
    {:reply, state.current_metrics, state}
  end

  @impl true
  def handle_call({:get_metrics_history, start_time, end_time}, _from, state) do
    filtered_history =
      state.metrics_history
      |> Enum.filter(fn %Metrics{timestamp: ts} ->
        ts >= start_time and ts <= end_time
      end)
      # Most recent first
      |> Enum.reverse()

    {:reply, filtered_history, state}
  end

  @impl true
  def handle_call({:get_aggregated_metrics, window_size}, _from, state) do
    window = window_size || state.aggregation_window
    now = System.system_time(:millisecond)
    start_time = now - window

    relevant_metrics =
      state.metrics_history
      |> Enum.filter(fn %Metrics{timestamp: ts} -> ts >= start_time end)

    aggregated = aggregate_metrics(relevant_metrics)
    {:reply, aggregated, state}
  end

  @impl true
  def handle_call(:get_stats, _from, state) do
    # Update memory usage
    memory_usage = :erlang.process_info(self(), :memory) |> elem(1)

    updated_stats = Map.put(state.stats, :memory_usage, memory_usage)
    {:reply, updated_stats, %{state | stats: updated_stats}}
  end

  @impl true
  def handle_cast(:collect_now, state) do
    new_state = perform_collection(state)
    {:noreply, new_state}
  end

  @impl true
  def handle_info(:collect_metrics, state) do
    new_state =
      state
      |> perform_collection()
      |> schedule_collection()

    {:noreply, new_state}
  end

  # Private functions

  defp perform_collection(state) do
    start_time = System.system_time(:millisecond)

    try do
      # Collect metrics from various sources
      connection_metrics = collect_connection_metrics()
      processing_metrics = collect_processing_metrics()
      deduplication_metrics = collect_deduplication_metrics()
      system_metrics = collect_system_metrics()

      # Calculate performance score
      performance_score =
        calculate_performance_score(
          connection_metrics,
          processing_metrics,
          deduplication_metrics,
          system_metrics
        )

      # Create metrics snapshot
      metrics = %Metrics{
        timestamp: start_time,
        connection_metrics: connection_metrics,
        processing_metrics: processing_metrics,
        deduplication_metrics: deduplication_metrics,
        system_metrics: system_metrics,
        performance_score: performance_score
      }

      # Update state
      new_history = add_to_history(state.metrics_history, metrics, state.retention_period)

      # Update stats
      stats =
        Map.merge(state.stats, %{
          collections_performed: state.stats.collections_performed + 1,
          last_collection_time: start_time
        })

      collection_time = System.system_time(:millisecond) - start_time

      Logger.debug("Metrics collected",
        collection_time_ms: collection_time,
        performance_score: performance_score,
        connections: length(Map.get(connection_metrics, :connections, [])),
        processing_rate: Map.get(processing_metrics, :events_per_second, 0)
      )

      %{state | current_metrics: metrics, metrics_history: new_history, stats: stats}
    rescue
      e ->
        Logger.error("Metrics collection failed", error: Exception.message(e))

        stats = Map.update(state.stats, :collection_errors, 1, &(&1 + 1))
        %{state | stats: stats}
    end
  end

  defp collect_connection_metrics do
    case ConnectionMonitor.get_connections() do
      {:ok, connections} ->
        %{
          total_connections: length(connections),
          connections: connections,
          healthy_connections: Enum.count(connections, &(&1.status == :connected)),
          average_ping: calculate_average_ping(connections),
          uptime_percentage: calculate_overall_uptime(connections)
        }

      {:error, reason} ->
        Logger.warning("Failed to collect connection metrics", reason: inspect(reason))
        %{total_connections: 0, connections: [], healthy_connections: 0}
    end
  end

  defp collect_processing_metrics do
    case Pipeline.get_stats() do
      pipeline_stats when is_map(pipeline_stats) ->
        total_processed = Map.get(pipeline_stats, :events_processed, 0)
        total_failed = Map.get(pipeline_stats, :events_failed, 0)
        avg_processing_time = Map.get(pipeline_stats, :average_processing_time, 0.0)

        # Calculate events per second based on average processing time
        events_per_second =
          if avg_processing_time > 0 do
            1000.0 / avg_processing_time
          else
            0.0
          end

        %{
          events_processed: total_processed,
          events_failed: total_failed,
          success_rate: calculate_success_rate(total_processed, total_failed),
          average_processing_time: avg_processing_time,
          events_per_second: events_per_second,
          batches_processed: Map.get(pipeline_stats, :batches_processed, 0)
        }

      error ->
        Logger.warning("Failed to collect pipeline metrics", reason: inspect(error))
        %{events_processed: 0, events_failed: 0, success_rate: 0.0}
    end
  end

  defp collect_deduplication_metrics do
    case Deduplicator.get_stats() do
      dedup_stats when is_map(dedup_stats) ->
        total_processed = Map.get(dedup_stats, :total_processed, 0)
        duplicates_found = Map.get(dedup_stats, :duplicates_found, 0)

        duplication_rate =
          if total_processed > 0 do
            duplicates_found / total_processed * 100.0
          else
            0.0
          end

        %{
          total_processed: total_processed,
          duplicates_found: duplicates_found,
          duplication_rate: duplication_rate,
          current_strategy: Map.get(dedup_stats, :current_strategy, :unknown),
          tracker_stats: Map.get(dedup_stats, :tracker_stats, %{})
        }

      error ->
        Logger.warning("Failed to collect deduplication metrics", reason: inspect(error))
        %{total_processed: 0, duplicates_found: 0, duplication_rate: 0.0}
    end
  end

  defp collect_system_metrics do
    # Collect only essential metrics to reduce memory usage
    %{
      memory_usage: :erlang.memory(:total),
      process_count: :erlang.system_info(:process_count)
      # Removed detailed stats to reduce memory consumption
    }
  end

  defp calculate_performance_score(
         connection_metrics,
         processing_metrics,
         deduplication_metrics,
         system_metrics
       ) do
    # Weighted performance scoring (0-100)
    connection_score = calculate_connection_score(connection_metrics) * 0.3
    processing_score = calculate_processing_score(processing_metrics) * 0.4
    deduplication_score = calculate_deduplication_score(deduplication_metrics) * 0.2
    system_score = calculate_system_score(system_metrics) * 0.1

    total_score = connection_score + processing_score + deduplication_score + system_score
    Float.round(total_score, 2)
  end

  defp calculate_connection_score(metrics) do
    total = Map.get(metrics, :total_connections, 0)
    healthy = Map.get(metrics, :healthy_connections, 0)
    uptime = Map.get(metrics, :uptime_percentage, 0.0)

    if total > 0 do
      health_ratio = healthy / total * 100.0
      (health_ratio + uptime) / 2.0
    else
      0.0
    end
  end

  defp calculate_processing_score(metrics) do
    success_rate = Map.get(metrics, :success_rate, 0.0)
    avg_time = Map.get(metrics, :average_processing_time, 999_999.0)

    # Score based on success rate and processing speed
    time_score =
      cond do
        avg_time < 10 -> 100.0
        avg_time < 50 -> 80.0
        avg_time < 100 -> 60.0
        avg_time < 500 -> 40.0
        true -> 20.0
      end

    (success_rate + time_score) / 2.0
  end

  defp calculate_deduplication_score(metrics) do
    duplication_rate = Map.get(metrics, :duplication_rate, 0.0)

    # Lower duplication rate is better
    cond do
      duplication_rate < 1.0 -> 100.0
      duplication_rate < 5.0 -> 90.0
      duplication_rate < 10.0 -> 80.0
      duplication_rate < 20.0 -> 70.0
      true -> 50.0
    end
  end

  defp calculate_system_score(metrics) do
    memory_usage = Map.get(metrics, :memory_usage, 0)
    process_count = Map.get(metrics, :process_count, 0)

    # Simple scoring based on resource usage
    memory_gb = memory_usage / (1024 * 1024 * 1024)

    memory_score =
      cond do
        memory_gb < 0.5 -> 100.0
        memory_gb < 1.0 -> 80.0
        memory_gb < 2.0 -> 60.0
        true -> 40.0
      end

    process_score =
      cond do
        process_count < 100 -> 100.0
        process_count < 500 -> 80.0
        process_count < 1000 -> 60.0
        true -> 40.0
      end

    (memory_score + process_score) / 2.0
  end

  defp calculate_average_ping([]), do: 0

  defp calculate_average_ping(connections) do
    ping_times =
      connections
      |> Enum.filter(&(Map.has_key?(&1, :ping_time) && !is_nil(&1.ping_time)))
      |> Enum.map(& &1.ping_time)

    case ping_times do
      [] -> 0
      times -> (Enum.sum(times) / length(times)) |> round()
    end
  end

  defp calculate_overall_uptime(connections) do
    if length(connections) > 0 do
      uptimes =
        Enum.map(
          connections,
          &WandererNotifier.Infrastructure.Messaging.HealthChecker.calculate_uptime_percentage/1
        )

      Enum.sum(uptimes) / length(uptimes)
    else
      0.0
    end
  end

  defp calculate_success_rate(processed, failed) do
    total = processed + failed

    if total > 0 do
      processed / total * 100.0
    else
      100.0
    end
  end

  defp add_to_history(history, new_metrics, retention_period) do
    cutoff_time = System.system_time(:millisecond) - retention_period

    # Add new metrics and filter old ones, with more aggressive limits
    [new_metrics | history]
    |> Enum.filter(fn %Metrics{timestamp: ts} -> ts >= cutoff_time end)
    # Limit history size more aggressively (was 1000, now 500)
    |> Enum.take(500)
  end

  defp aggregate_metrics([]), do: nil

  defp aggregate_metrics(metrics_list) do
    count = length(metrics_list)

    %{
      time_range: {
        List.last(metrics_list).timestamp,
        List.first(metrics_list).timestamp
      },
      sample_count: count,
      average_performance_score: average_field(metrics_list, :performance_score),
      total_events_processed:
        sum_nested_field(metrics_list, [:processing_metrics, :events_processed]),
      total_events_failed: sum_nested_field(metrics_list, [:processing_metrics, :events_failed]),
      average_processing_time:
        average_nested_field(metrics_list, [:processing_metrics, :average_processing_time]),
      total_duplicates:
        sum_nested_field(metrics_list, [:deduplication_metrics, :duplicates_found]),
      average_connection_health:
        average_nested_field(metrics_list, [:connection_metrics, :uptime_percentage])
    }
  end

  defp average_field(metrics_list, field) do
    values = metrics_list |> Enum.map(&Map.get(&1, field, 0)) |> Enum.filter(&is_number/1)
    if length(values) > 0, do: Enum.sum(values) / length(values), else: 0.0
  end

  defp sum_nested_field(metrics_list, path) do
    metrics_list
    |> Enum.map(fn metric ->
      # Convert struct to map to use get_in
      metric_map = Map.from_struct(metric)
      get_in(metric_map, path)
    end)
    |> Enum.filter(&is_number/1)
    |> Enum.sum()
  end

  defp average_nested_field(metrics_list, path) do
    values =
      metrics_list
      |> Enum.map(fn metric ->
        # Convert struct to map to use get_in
        metric_map = Map.from_struct(metric)
        get_in(metric_map, path)
      end)
      |> Enum.filter(&is_number/1)

    if length(values) > 0, do: Enum.sum(values) / length(values), else: 0.0
  end

  defp schedule_collection(state) do
    timer = Process.send_after(self(), :collect_metrics, state.collection_interval)
    %{state | collection_timer: timer}
  end
end
