defmodule WandererNotifier.Metrics.Dashboard do
  @moduledoc """
  Real-time metrics dashboard for monitoring system performance.

  Provides web-based dashboard endpoints for visualizing collected metrics,
  connection health, processing statistics, and system performance trends.
  """

  use GenServer
  require Logger

  alias WandererNotifier.Metrics.Collector
  alias WandererNotifier.Realtime.{ConnectionMonitor, HealthChecker}

  # Dashboard configuration
  # 5 seconds
  @default_refresh_interval 5_000
  # 5 minutes of data at 5-second intervals
  @default_chart_points 60

  defmodule State do
    @moduledoc """
    Dashboard state structure.
    """

    defstruct [
      :refresh_interval,
      :chart_points,
      :dashboard_data,
      :refresh_timer,
      :subscribers
    ]
  end

  @doc """
  Starts the metrics dashboard.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Gets the current dashboard data.
  """
  def get_dashboard_data do
    GenServer.call(__MODULE__, :get_dashboard_data)
  end

  @doc """
  Gets connection health summary.
  """
  def get_connection_summary do
    GenServer.call(__MODULE__, :get_connection_summary)
  end

  @doc """
  Gets processing performance summary.
  """
  def get_processing_summary do
    GenServer.call(__MODULE__, :get_processing_summary)
  end

  @doc """
  Gets system resource summary.
  """
  def get_system_summary do
    GenServer.call(__MODULE__, :get_system_summary)
  end

  @doc """
  Gets historical chart data for a specific metric.
  """
  def get_chart_data(metric_name, time_range \\ :last_hour) do
    GenServer.call(__MODULE__, {:get_chart_data, metric_name, time_range})
  end

  @doc """
  Subscribes to real-time dashboard updates.
  """
  def subscribe do
    GenServer.cast(__MODULE__, {:subscribe, self()})
  end

  @doc """
  Unsubscribes from dashboard updates.
  """
  def unsubscribe do
    GenServer.cast(__MODULE__, {:unsubscribe, self()})
  end

  # Server Implementation

  @impl true
  def init(opts) do
    refresh_interval = Keyword.get(opts, :refresh_interval, @default_refresh_interval)
    chart_points = Keyword.get(opts, :chart_points, @default_chart_points)

    state = %State{
      refresh_interval: refresh_interval,
      chart_points: chart_points,
      dashboard_data: nil,
      refresh_timer: nil,
      subscribers: MapSet.new()
    }

    # Generate initial dashboard data
    initial_state = refresh_dashboard_data(state)

    # Schedule periodic refresh
    schedule_refresh(initial_state)

    Logger.info("Metrics dashboard started",
      refresh_interval_seconds: div(refresh_interval, 1000)
    )

    {:ok, initial_state}
  end

  @impl true
  def handle_call(:get_dashboard_data, _from, state) do
    {:reply, state.dashboard_data, state}
  end

  @impl true
  def handle_call(:get_connection_summary, _from, state) do
    summary = generate_connection_summary()
    {:reply, summary, state}
  end

  @impl true
  def handle_call(:get_processing_summary, _from, state) do
    summary = generate_processing_summary()
    {:reply, summary, state}
  end

  @impl true
  def handle_call(:get_system_summary, _from, state) do
    summary = generate_system_summary()
    {:reply, summary, state}
  end

  @impl true
  def handle_call({:get_chart_data, metric_name, time_range}, _from, state) do
    chart_data = generate_chart_data(metric_name, time_range, state.chart_points)
    {:reply, chart_data, state}
  end

  @impl true
  def handle_cast({:subscribe, pid}, state) do
    Process.monitor(pid)
    new_subscribers = MapSet.put(state.subscribers, pid)
    {:noreply, %{state | subscribers: new_subscribers}}
  end

  @impl true
  def handle_cast({:unsubscribe, pid}, state) do
    new_subscribers = MapSet.delete(state.subscribers, pid)
    {:noreply, %{state | subscribers: new_subscribers}}
  end

  @impl true
  def handle_info(:refresh_dashboard, state) do
    new_state =
      state
      |> refresh_dashboard_data()
      |> notify_subscribers()
      |> schedule_refresh()

    {:noreply, new_state}
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    # Remove subscriber that went down
    new_subscribers = MapSet.delete(state.subscribers, pid)
    {:noreply, %{state | subscribers: new_subscribers}}
  end

  # Private functions

  defp refresh_dashboard_data(state) do
    dashboard_data = %{
      timestamp: System.monotonic_time(:millisecond),
      overview: generate_overview(),
      connections: generate_connection_summary(),
      processing: generate_processing_summary(),
      system: generate_system_summary(),
      alerts: generate_alerts()
    }

    %{state | dashboard_data: dashboard_data}
  end

  defp generate_overview do
    current_metrics = Collector.get_current_metrics()

    case current_metrics do
      %{performance_score: score} = metrics ->
        %{
          overall_health: determine_health_status(score),
          performance_score: score,
          last_updated: metrics.timestamp,
          status: :operational,
          uptime: calculate_system_uptime()
        }

      _ ->
        %{
          overall_health: :unknown,
          performance_score: 0.0,
          last_updated: nil,
          status: :initializing,
          uptime: 0
        }
    end
  end

  defp generate_connection_summary do
    case ConnectionMonitor.get_all_connections() do
      {:ok, connections} ->
        health_reports = Enum.map(connections, &HealthChecker.generate_health_report/1)

        %{
          total_connections: length(connections),
          healthy_connections: Enum.count(health_reports, &(&1.quality in [:excellent, :good])),
          connections_by_type: group_connections_by_type(connections),
          connections_by_status: group_connections_by_status(connections),
          average_ping: ConnectionMonitor.get_average_ping(),
          connection_details: health_reports
        }

      {:error, reason} ->
        Logger.warning("Failed to generate connection summary", reason: inspect(reason))

        %{
          total_connections: 0,
          healthy_connections: 0,
          connections_by_type: %{},
          connections_by_status: %{},
          average_ping: nil,
          connection_details: []
        }
    end
  end

  defp generate_processing_summary do
    current_metrics = Collector.get_current_metrics()
    aggregated = Collector.get_aggregated_metrics()

    processing_metrics =
      case current_metrics do
        %{processing_metrics: metrics} -> metrics
        _ -> %{}
      end

    %{
      current_throughput: Map.get(processing_metrics, :events_per_second, 0.0),
      total_processed: Map.get(processing_metrics, :events_processed, 0),
      total_failed: Map.get(processing_metrics, :events_failed, 0),
      success_rate: Map.get(processing_metrics, :success_rate, 100.0),
      average_processing_time: Map.get(processing_metrics, :average_processing_time, 0.0),
      batch_statistics: get_batch_statistics(processing_metrics),
      trend_data: extract_trend_data(aggregated)
    }
  end

  defp generate_system_summary do
    current_metrics = Collector.get_current_metrics()

    system_metrics =
      case current_metrics do
        %{system_metrics: metrics} -> metrics
        _ -> %{}
      end

    memory_usage = Map.get(system_metrics, :memory_usage, 0)
    process_count = Map.get(system_metrics, :process_count, 0)

    %{
      memory_usage: %{
        total_bytes: memory_usage,
        total_mb: Float.round(memory_usage / (1024 * 1024), 2),
        total_gb: Float.round(memory_usage / (1024 * 1024 * 1024), 3)
      },
      process_count: process_count,
      cpu_usage: Map.get(system_metrics, :cpu_usage, 0.0),
      uptime_seconds: Map.get(system_metrics, :uptime, 0),
      gc_statistics: Map.get(system_metrics, :gc_statistics, {0, 0}),
      resource_alerts: generate_resource_alerts(system_metrics)
    }
  end

  defp generate_alerts do
    alerts = []

    # Check connection health
    alerts =
      case generate_connection_summary() do
        %{healthy_connections: healthy, total_connections: total} when total > 0 ->
          health_ratio = healthy / total

          if health_ratio < 0.8 do
            [
              %{type: :warning, message: "Connection health below 80%", severity: :medium}
              | alerts
            ]
          else
            alerts
          end

        _ ->
          alerts
      end

    # Check processing performance
    alerts =
      case Collector.get_current_metrics() do
        %{processing_metrics: %{success_rate: rate}} when rate < 95.0 ->
          [
            %{type: :error, message: "Processing success rate below 95%", severity: :high}
            | alerts
          ]

        _ ->
          alerts
      end

    # Check system resources
    alerts =
      case generate_system_summary() do
        %{memory_usage: %{total_gb: gb}} when gb > 2.0 ->
          [%{type: :warning, message: "High memory usage detected", severity: :medium} | alerts]

        _ ->
          alerts
      end

    alerts
  end

  defp generate_chart_data(metric_name, time_range, max_points) do
    {start_time, end_time} = get_time_range(time_range)

    history = Collector.get_metrics_history(start_time, end_time)

    # Extract specific metric data
    data_points =
      history
      |> Enum.map(&extract_metric_value(&1, metric_name))
      |> Enum.filter(& &1)
      |> Enum.take(max_points)
      # Chronological order
      |> Enum.reverse()

    %{
      metric_name: metric_name,
      time_range: {start_time, end_time},
      data_points: data_points,
      min_value:
        if(length(data_points) > 0,
          do: Enum.min_by(data_points, &elem(&1, 1)) |> elem(1),
          else: 0
        ),
      max_value:
        if(length(data_points) > 0,
          do: Enum.max_by(data_points, &elem(&1, 1)) |> elem(1),
          else: 0
        )
    }
  end

  defp extract_metric_value(metrics, metric_name) do
    value =
      case metric_name do
        :performance_score -> metrics.performance_score
        :events_per_second -> get_in(metrics, [:processing_metrics, :events_per_second])
        :success_rate -> get_in(metrics, [:processing_metrics, :success_rate])
        :memory_usage -> get_in(metrics, [:system_metrics, :memory_usage])
        :connection_count -> get_in(metrics, [:connection_metrics, :total_connections])
        :duplication_rate -> get_in(metrics, [:deduplication_metrics, :duplication_rate])
        _ -> nil
      end

    if is_number(value) do
      {metrics.timestamp, value}
    else
      nil
    end
  end

  defp get_time_range(time_range) do
    now = System.monotonic_time(:millisecond)

    case time_range do
      :last_hour -> {now - 3_600_000, now}
      :last_6_hours -> {now - 21_600_000, now}
      :last_24_hours -> {now - 86_400_000, now}
      :last_week -> {now - 604_800_000, now}
      # Default to last hour
      _ -> {now - 3_600_000, now}
    end
  end

  defp determine_health_status(score) when is_number(score) do
    cond do
      score >= 90 -> :excellent
      score >= 75 -> :good
      score >= 50 -> :fair
      score >= 25 -> :poor
      true -> :critical
    end
  end

  defp determine_health_status(_), do: :unknown

  defp group_connections_by_type(connections) do
    connections
    |> Enum.group_by(& &1.type)
    |> Enum.map(fn {type, conns} -> {type, length(conns)} end)
    |> Map.new()
  end

  defp group_connections_by_status(connections) do
    connections
    |> Enum.group_by(& &1.status)
    |> Enum.map(fn {status, conns} -> {status, length(conns)} end)
    |> Map.new()
  end

  defp get_batch_statistics(processing_metrics) do
    %{
      batches_processed: Map.get(processing_metrics, :batches_processed, 0),
      average_batch_size: calculate_average_batch_size(processing_metrics)
    }
  end

  defp calculate_average_batch_size(metrics) do
    events = Map.get(metrics, :events_processed, 0)
    batches = Map.get(metrics, :batches_processed, 0)

    if batches > 0, do: Float.round(events / batches, 2), else: 0.0
  end

  defp extract_trend_data(nil), do: %{}

  defp extract_trend_data(aggregated) do
    %{
      total_events: Map.get(aggregated, :total_events_processed, 0),
      total_failures: Map.get(aggregated, :total_events_failed, 0),
      average_processing_time: Map.get(aggregated, :average_processing_time, 0.0)
    }
  end

  defp generate_resource_alerts(system_metrics) do
    alerts = []

    memory_usage = Map.get(system_metrics, :memory_usage, 0)
    process_count = Map.get(system_metrics, :process_count, 0)

    # 2GB
    alerts =
      if memory_usage > 2 * 1024 * 1024 * 1024 do
        ["High memory usage" | alerts]
      else
        alerts
      end

    alerts =
      if process_count > 1000 do
        ["High process count" | alerts]
      else
        alerts
      end

    alerts
  end

  defp calculate_system_uptime do
    {uptime_ms, _} = :erlang.statistics(:wall_clock)
    # Convert to seconds
    div(uptime_ms, 1000)
  end

  defp notify_subscribers(state) do
    if MapSet.size(state.subscribers) > 0 do
      message = {:dashboard_update, state.dashboard_data}

      Enum.each(state.subscribers, fn pid ->
        send(pid, message)
      end)
    end

    state
  end

  defp schedule_refresh(state) do
    timer = Process.send_after(self(), :refresh_dashboard, state.refresh_interval)
    %{state | refresh_timer: timer}
  end
end
