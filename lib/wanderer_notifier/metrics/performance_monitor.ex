defmodule WandererNotifier.Metrics.PerformanceMonitor do
  @moduledoc """
  Performance monitoring system with adaptive thresholds and alerting.

  Monitors system performance metrics, detects anomalies, and provides
  adaptive alerting based on historical performance patterns.
  """

  use GenServer
  require Logger

  alias WandererNotifier.Metrics.Collector

  # Monitoring configuration
  # 10 seconds
  @default_monitoring_interval 10_000
  # 5 minutes
  @default_alert_cooldown 300_000
  # 1 hour
  @default_baseline_window 3_600_000

  # Performance thresholds
  @performance_thresholds %{
    critical: 25.0,
    poor: 50.0,
    fair: 75.0,
    good: 90.0
  }

  # Anomaly detection settings
  @anomaly_detection %{
    # 2x normal usage
    memory_spike_threshold: 2.0,
    # 5x normal processing time
    processing_time_spike: 5.0,
    # 3x normal error rate
    error_rate_spike: 3.0,
    # 50% connection drop
    connection_drop_threshold: 0.5
  }

  defmodule State do
    @moduledoc """
    Performance monitor state structure.
    """

    defstruct [
      :monitoring_interval,
      :alert_cooldown,
      :baseline_window,
      :performance_baseline,
      :recent_alerts,
      :monitoring_timer,
      :anomaly_history,
      :stats
    ]
  end

  defmodule Alert do
    @moduledoc """
    Performance alert structure.
    """

    defstruct [
      :id,
      :type,
      :severity,
      :message,
      :timestamp,
      :metric_name,
      :current_value,
      :threshold_value,
      :resolved_at
    ]
  end

  @doc """
  Starts the performance monitor.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Gets current performance status.
  """
  def get_performance_status do
    GenServer.call(__MODULE__, :get_performance_status)
  end

  @doc """
  Gets active alerts.
  """
  def get_active_alerts do
    GenServer.call(__MODULE__, :get_active_alerts)
  end

  @doc """
  Gets performance baseline statistics.
  """
  def get_baseline_stats do
    GenServer.call(__MODULE__, :get_baseline_stats)
  end

  @doc """
  Gets anomaly detection history.
  """
  def get_anomaly_history(limit \\ 50) do
    GenServer.call(__MODULE__, {:get_anomaly_history, limit})
  end

  @doc """
  Forces immediate performance check.
  """
  def check_performance_now do
    GenServer.cast(__MODULE__, :check_performance_now)
  end

  @doc """
  Updates performance thresholds.
  """
  def update_thresholds(new_thresholds) do
    GenServer.cast(__MODULE__, {:update_thresholds, new_thresholds})
  end

  # Server Implementation

  @impl true
  def init(opts) do
    monitoring_interval = Keyword.get(opts, :monitoring_interval, @default_monitoring_interval)
    alert_cooldown = Keyword.get(opts, :alert_cooldown, @default_alert_cooldown)
    baseline_window = Keyword.get(opts, :baseline_window, @default_baseline_window)

    state = %State{
      monitoring_interval: monitoring_interval,
      alert_cooldown: alert_cooldown,
      baseline_window: baseline_window,
      performance_baseline: nil,
      recent_alerts: [],
      monitoring_timer: nil,
      anomaly_history: [],
      stats: %{
        checks_performed: 0,
        alerts_generated: 0,
        anomalies_detected: 0,
        last_check_time: nil
      }
    }

    # Start monitoring
    schedule_monitoring(state)

    Logger.info("Performance monitor started",
      monitoring_interval_seconds: div(monitoring_interval, 1000),
      baseline_window_minutes: div(baseline_window, 60_000)
    )

    {:ok, state}
  end

  @impl true
  def handle_call(:get_performance_status, _from, state) do
    status = generate_performance_status(state)
    {:reply, status, state}
  end

  @impl true
  def handle_call(:get_active_alerts, _from, state) do
    active_alerts = get_active_alerts_list(state.recent_alerts)
    {:reply, active_alerts, state}
  end

  @impl true
  def handle_call(:get_baseline_stats, _from, state) do
    {:reply, state.performance_baseline, state}
  end

  @impl true
  def handle_call({:get_anomaly_history, limit}, _from, state) do
    history = Enum.take(state.anomaly_history, limit)
    {:reply, history, state}
  end

  @impl true
  def handle_cast(:check_performance_now, state) do
    new_state = perform_performance_check(state)
    {:noreply, new_state}
  end

  @impl true
  def handle_cast({:update_thresholds, _new_thresholds}, state) do
    # For now, we use static thresholds, but this could be expanded
    Logger.info("Performance thresholds update requested")
    {:noreply, state}
  end

  @impl true
  def handle_info(:monitor_performance, state) do
    new_state =
      state
      |> perform_performance_check()
      |> schedule_monitoring()

    {:noreply, new_state}
  end

  # Private functions

  defp perform_performance_check(state) do
    start_time = System.monotonic_time(:millisecond)

    try do
      current_metrics = Collector.get_current_metrics()

      state
      |> process_metrics(current_metrics, start_time)
      |> log_anomalies_if_present()
    rescue
      e ->
        Logger.error("Performance check failed", error: Exception.message(e))
        state
    end
  end

  defp process_metrics(state, current_metrics, start_time) do
    updated_baseline =
      update_performance_baseline(
        state.performance_baseline,
        current_metrics,
        state.baseline_window
      )

    anomalies = detect_anomalies(current_metrics, updated_baseline)

    new_alerts =
      generate_alerts_for_anomalies(anomalies, state.recent_alerts, state.alert_cooldown)

    state
    |> update_anomaly_history(anomalies, current_metrics, start_time)
    |> update_performance_stats(anomalies, new_alerts, start_time)
    |> update_state_fields(updated_baseline, new_alerts)
  end

  defp update_anomaly_history(state, [], _, _), do: state

  defp update_anomaly_history(state, anomalies, current_metrics, start_time) do
    anomaly_entry = %{
      timestamp: start_time,
      anomalies: anomalies,
      performance_score: get_performance_score(current_metrics)
    }

    %{state | anomaly_history: [anomaly_entry | Enum.take(state.anomaly_history, 99)]}
  end

  defp update_performance_stats(state, anomalies, new_alerts, start_time) do
    updated_stats =
      Map.merge(state.stats, %{
        checks_performed: state.stats.checks_performed + 1,
        alerts_generated: state.stats.alerts_generated + length(new_alerts),
        anomalies_detected: state.stats.anomalies_detected + length(anomalies),
        last_check_time: start_time
      })

    %{state | stats: updated_stats}
  end

  defp update_state_fields(state, updated_baseline, new_alerts) do
    %{
      state
      | performance_baseline: updated_baseline,
        recent_alerts: new_alerts ++ state.recent_alerts
    }
  end

  defp log_anomalies_if_present(%{anomaly_history: history} = state) do
    case history do
      [%{anomalies: anomalies} | _] when length(anomalies) > 0 ->
        Logger.warning("Performance anomalies detected",
          anomaly_count: length(anomalies),
          new_alerts: length(state.recent_alerts)
        )

      _ ->
        :ok
    end

    state
  end

  defp update_performance_baseline(nil, current_metrics, _window) do
    # Initialize baseline with current metrics
    case current_metrics do
      %{} = metrics ->
        %{
          created_at: System.monotonic_time(:millisecond),
          performance_score: get_performance_score(metrics),
          processing_metrics: extract_processing_baseline(metrics),
          system_metrics: extract_system_baseline(metrics),
          connection_metrics: extract_connection_baseline(metrics)
        }

      _ ->
        nil
    end
  end

  defp update_performance_baseline(baseline, current_metrics, window) do
    case {baseline, current_metrics} do
      {%{created_at: created_at} = baseline, %{} = metrics} ->
        now = System.monotonic_time(:millisecond)

        # Update baseline if window has passed
        if now - created_at > window do
          update_performance_baseline(nil, metrics, window)
        else
          # Gradually update baseline with current metrics (exponential smoothing)
          # Smoothing factor
          alpha = 0.1

          %{
            baseline
            | performance_score:
                smooth_value(baseline.performance_score, get_performance_score(metrics), alpha),
              processing_metrics:
                smooth_processing_metrics(baseline.processing_metrics, metrics, alpha),
              system_metrics: smooth_system_metrics(baseline.system_metrics, metrics, alpha),
              connection_metrics:
                smooth_connection_metrics(baseline.connection_metrics, metrics, alpha)
          }
        end

      _ ->
        baseline
    end
  end

  defp detect_anomalies(_current_metrics, baseline) when is_nil(baseline), do: []

  defp detect_anomalies(current_metrics, baseline) do
    anomalies = []

    # Check performance score anomaly
    anomalies =
      case get_performance_score(current_metrics) do
        score when is_number(score) ->
          # 30% drop
          if score < baseline.performance_score * 0.7 do
            [
              %{
                type: :performance_degradation,
                severity: :high,
                current: score,
                baseline: baseline.performance_score
              }
              | anomalies
            ]
          else
            anomalies
          end

        _ ->
          anomalies
      end

    # Check processing anomalies
    anomalies = anomalies ++ detect_processing_anomalies(current_metrics, baseline)

    # Check system anomalies
    anomalies = anomalies ++ detect_system_anomalies(current_metrics, baseline)

    # Check connection anomalies
    anomalies = anomalies ++ detect_connection_anomalies(current_metrics, baseline)

    anomalies
  end

  defp detect_processing_anomalies(current_metrics, baseline) do
    anomalies = []

    processing_metrics = Map.get(current_metrics, :processing_metrics, %{})
    baseline_processing = Map.get(baseline, :processing_metrics, %{})

    # Check processing time spike
    current_time = Map.get(processing_metrics, :average_processing_time, 0)
    baseline_time = Map.get(baseline_processing, :average_processing_time, 0)

    anomalies =
      if baseline_time > 0 and
           current_time > baseline_time * @anomaly_detection.processing_time_spike do
        [
          %{
            type: :processing_time_spike,
            severity: :medium,
            current: current_time,
            baseline: baseline_time
          }
          | anomalies
        ]
      else
        anomalies
      end

    # Check error rate spike
    current_success = Map.get(processing_metrics, :success_rate, 100.0)
    baseline_success = Map.get(baseline_processing, :success_rate, 100.0)

    # 20% drop in success rate
    anomalies =
      if current_success < baseline_success * 0.8 do
        [
          %{
            type: :error_rate_spike,
            severity: :high,
            current: 100.0 - current_success,
            baseline: 100.0 - baseline_success
          }
          | anomalies
        ]
      else
        anomalies
      end

    anomalies
  end

  defp detect_system_anomalies(current_metrics, baseline) do
    anomalies = []

    system_metrics = Map.get(current_metrics, :system_metrics, %{})
    baseline_system = Map.get(baseline, :system_metrics, %{})

    # Check memory spike
    current_memory = Map.get(system_metrics, :memory_usage, 0)
    baseline_memory = Map.get(baseline_system, :memory_usage, 0)

    anomalies =
      if baseline_memory > 0 and
           current_memory > baseline_memory * @anomaly_detection.memory_spike_threshold do
        [
          %{
            type: :memory_spike,
            severity: :medium,
            current: current_memory,
            baseline: baseline_memory
          }
          | anomalies
        ]
      else
        anomalies
      end

    anomalies
  end

  defp detect_connection_anomalies(current_metrics, baseline) do
    anomalies = []

    connection_metrics = Map.get(current_metrics, :connection_metrics, %{})
    baseline_connection = Map.get(baseline, :connection_metrics, %{})

    # Check connection drop
    current_connections = Map.get(connection_metrics, :total_connections, 0)
    baseline_connections = Map.get(baseline_connection, :total_connections, 0)

    anomalies =
      if baseline_connections > 0 and
           current_connections <
             baseline_connections * @anomaly_detection.connection_drop_threshold do
        [
          %{
            type: :connection_drop,
            severity: :high,
            current: current_connections,
            baseline: baseline_connections
          }
          | anomalies
        ]
      else
        anomalies
      end

    anomalies
  end

  defp generate_alerts_for_anomalies(anomalies, recent_alerts, cooldown) do
    now = System.monotonic_time(:millisecond)

    # Filter out alerts that are in cooldown
    active_alert_types =
      recent_alerts
      |> Enum.filter(fn alert ->
        is_nil(alert.resolved_at) and now - alert.timestamp < cooldown
      end)
      |> Enum.map(& &1.type)
      |> MapSet.new()

    # Generate new alerts for anomalies not in cooldown
    anomalies
    |> Enum.reject(fn anomaly -> MapSet.member?(active_alert_types, anomaly.type) end)
    |> Enum.map(fn anomaly ->
      %Alert{
        id: generate_alert_id(),
        type: anomaly.type,
        severity: anomaly.severity,
        message: generate_alert_message(anomaly),
        timestamp: now,
        metric_name: to_string(anomaly.type),
        current_value: anomaly.current,
        threshold_value: anomaly.baseline,
        resolved_at: nil
      }
    end)
  end

  defp generate_performance_status(state) do
    current_metrics = Collector.get_current_metrics()
    active_alerts = get_active_alerts_list(state.recent_alerts)
    performance_score = get_performance_score(current_metrics)

    %{
      overall_health: calculate_overall_health(performance_score),
      performance_score: performance_score,
      active_alerts_count: length(active_alerts),
      active_alerts: active_alerts,
      baseline_available: not is_nil(state.performance_baseline),
      last_check: state.stats.last_check_time,
      monitoring_stats: state.stats
    }
  end

  defp calculate_overall_health(score) when is_number(score) do
    cond do
      score >= @performance_thresholds.good -> :excellent
      score >= @performance_thresholds.fair -> :good
      score >= @performance_thresholds.poor -> :fair
      score >= @performance_thresholds.critical -> :poor
      true -> :critical
    end
  end

  defp calculate_overall_health(_), do: :unknown

  defp get_active_alerts_list(recent_alerts) do
    recent_alerts
    |> Enum.filter(fn alert -> is_nil(alert.resolved_at) end)
    # Limit to most recent 20 alerts
    |> Enum.take(20)
  end

  defp get_performance_score(nil), do: 0.0
  defp get_performance_score(%{performance_score: score}), do: score
  defp get_performance_score(_), do: 0.0

  defp extract_processing_baseline(%{processing_metrics: metrics}), do: metrics
  defp extract_processing_baseline(_), do: %{}

  defp extract_system_baseline(%{system_metrics: metrics}), do: metrics
  defp extract_system_baseline(_), do: %{}

  defp extract_connection_baseline(%{connection_metrics: metrics}), do: metrics
  defp extract_connection_baseline(_), do: %{}

  defp smooth_value(baseline_value, current_value, alpha)
       when is_number(baseline_value) and is_number(current_value) do
    baseline_value * (1 - alpha) + current_value * alpha
  end

  defp smooth_value(baseline_value, _current_value, _alpha), do: baseline_value

  defp smooth_processing_metrics(baseline, %{processing_metrics: current}, alpha) do
    smooth_metrics_map(baseline, current, alpha)
  end

  defp smooth_processing_metrics(baseline, _current, _alpha), do: baseline

  defp smooth_system_metrics(baseline, %{system_metrics: current}, alpha) do
    smooth_metrics_map(baseline, current, alpha)
  end

  defp smooth_system_metrics(baseline, _current, _alpha), do: baseline

  defp smooth_connection_metrics(baseline, %{connection_metrics: current}, alpha) do
    smooth_metrics_map(baseline, current, alpha)
  end

  defp smooth_connection_metrics(baseline, _current, _alpha), do: baseline

  defp smooth_metrics_map(baseline, current, alpha) do
    Enum.reduce(baseline, baseline, fn {key, baseline_value}, acc ->
      current_value = Map.get(current, key)
      smoothed_value = smooth_value(baseline_value, current_value, alpha)
      Map.put(acc, key, smoothed_value)
    end)
  end

  defp generate_alert_id do
    :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
  end

  defp generate_alert_message(anomaly) do
    case anomaly.type do
      :performance_degradation ->
        "Performance score dropped to #{Float.round(anomaly.current, 1)} (baseline: #{Float.round(anomaly.baseline, 1)})"

      :processing_time_spike ->
        "Processing time increased to #{Float.round(anomaly.current, 1)}ms (baseline: #{Float.round(anomaly.baseline, 1)}ms)"

      :error_rate_spike ->
        "Error rate increased to #{Float.round(anomaly.current, 1)}% (baseline: #{Float.round(anomaly.baseline, 1)}%)"

      :memory_spike ->
        memory_mb = Float.round(anomaly.current / (1024 * 1024), 1)
        baseline_mb = Float.round(anomaly.baseline / (1024 * 1024), 1)
        "Memory usage spiked to #{memory_mb}MB (baseline: #{baseline_mb}MB)"

      :connection_drop ->
        "Connection count dropped to #{anomaly.current} (baseline: #{anomaly.baseline})"

      _ ->
        "Performance anomaly detected: #{anomaly.type}"
    end
  end

  defp schedule_monitoring(state) do
    timer = Process.send_after(self(), :monitor_performance, state.monitoring_interval)
    %{state | monitoring_timer: timer}
  end
end
