defmodule WandererNotifier.Cache.PerformanceMonitor do
  @moduledoc """
  Real-time cache performance monitoring and alerting.

  This module provides continuous monitoring of cache performance metrics,
  alerting on performance degradation, and automatic optimization suggestions.

  ## Features

  - Real-time performance monitoring
  - Configurable performance thresholds
  - Automatic alerting on performance degradation
  - Performance trend analysis
  - Optimization recommendations
  - Integration with telemetry and logging systems

  ## Configuration

  The monitor can be configured with various thresholds and intervals:

  ```elixir
  config :wanderer_notifier, WandererNotifier.Cache.PerformanceMonitor,
    monitoring_interval: 30_000,  # 30 seconds
    hit_ratio_threshold: 0.90,    # 90% hit ratio
    response_time_threshold: 100, # 100ms
    alert_cooldown: 300_000       # 5 minutes
  ```

  ## Usage

  ```elixir
  # Start monitoring
  WandererNotifier.Cache.PerformanceMonitor.start_monitoring()

  # Check current status
  status = WandererNotifier.Cache.PerformanceMonitor.get_status()

  # Get performance report
  report = WandererNotifier.Cache.PerformanceMonitor.get_performance_report()
  ```
  """

  use GenServer
  require Logger

  alias WandererNotifier.Cache.Metrics

  @type performance_status :: :healthy | :degraded | :critical
  @type alert_type ::
          :hit_ratio_low | :response_time_high | :memory_usage_high | :eviction_rate_high
  @type threshold_config :: %{
          hit_ratio_threshold: float(),
          response_time_threshold: number(),
          memory_usage_threshold: number(),
          eviction_rate_threshold: number()
        }

  # Default configuration
  @default_config %{
    # 30 seconds
    monitoring_interval: 30_000,
    # 90% hit ratio
    hit_ratio_threshold: 0.90,
    # 100ms average response time
    response_time_threshold: 100,
    # 80% memory usage
    memory_usage_threshold: 0.80,
    # 10% eviction rate
    eviction_rate_threshold: 0.10,
    # 5 minutes between alerts
    alert_cooldown: 300_000,
    # Number of samples for trend analysis
    trend_analysis_window: 10
  }

  @doc """
  Starts the performance monitor GenServer.

  ## Options
  - All options from @default_config can be overridden
  - `:name` - Name for the GenServer (default: __MODULE__)
  """
  def start_link(opts \\ []) do
    {name, opts} = Keyword.pop(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Starts performance monitoring.

  ## Returns
  :ok
  """
  @spec start_monitoring() :: :ok
  def start_monitoring do
    GenServer.call(__MODULE__, :start_monitoring)
  end

  @doc """
  Stops performance monitoring.

  ## Returns
  :ok
  """
  @spec stop_monitoring() :: :ok
  def stop_monitoring do
    GenServer.call(__MODULE__, :stop_monitoring)
  end

  @doc """
  Gets current performance status.

  ## Returns
  Map containing current performance status and metrics
  """
  @spec get_status() :: map()
  def get_status do
    GenServer.call(__MODULE__, :get_status)
  end

  @doc """
  Gets detailed performance report.

  ## Returns
  Map containing comprehensive performance analysis
  """
  @spec get_performance_report() :: map()
  def get_performance_report do
    GenServer.call(__MODULE__, :get_performance_report)
  end

  @doc """
  Updates monitoring configuration.

  ## Parameters
  - config: Map with configuration updates

  ## Returns
  :ok
  """
  @spec update_config(map()) :: :ok
  def update_config(config) do
    GenServer.call(__MODULE__, {:update_config, config})
  end

  @doc """
  Forces a performance check.

  ## Returns
  Map with performance check results
  """
  @spec force_check() :: map()
  def force_check do
    GenServer.call(__MODULE__, :force_check)
  end

  @doc """
  Gets optimization recommendations based on current performance.

  ## Returns
  List of optimization recommendations
  """
  @spec get_recommendations() :: [map()]
  def get_recommendations do
    GenServer.call(__MODULE__, :get_recommendations)
  end

  # GenServer callbacks

  @impl GenServer
  def init(opts) do
    config = Map.merge(@default_config, Map.new(opts))

    # Start monitoring automatically unless explicitly disabled
    auto_start = Keyword.get(opts, :auto_start, true)

    state = %{
      config: config,
      monitoring_active: false,
      current_status: :healthy,
      last_check: nil,
      performance_history: [],
      alerts: %{},
      recommendations: []
    }

    # Automatically start monitoring if enabled
    if auto_start do
      schedule_monitoring(config.monitoring_interval)
      Logger.info("Cache performance monitor initialized and started")
      {:ok, %{state | monitoring_active: true}}
    else
      Logger.info("Cache performance monitor initialized (not started)")
      {:ok, state}
    end
  end

  @impl GenServer
  def handle_call(:start_monitoring, _from, state) do
    if state.monitoring_active do
      {:reply, :ok, state}
    else
      schedule_monitoring(state.config.monitoring_interval)
      new_state = %{state | monitoring_active: true}
      Logger.info("Cache performance monitoring started")
      {:reply, :ok, new_state}
    end
  end

  @impl GenServer
  def handle_call(:stop_monitoring, _from, state) do
    new_state = %{state | monitoring_active: false}
    Logger.info("Cache performance monitoring stopped")
    {:reply, :ok, new_state}
  end

  @impl GenServer
  def handle_call(:get_status, _from, state) do
    status = build_status_response(state)
    {:reply, status, state}
  end

  @impl GenServer
  def handle_call(:get_performance_report, _from, state) do
    report = build_performance_report(state)
    {:reply, report, state}
  end

  @impl GenServer
  def handle_call({:update_config, config_updates}, _from, state) do
    new_config = Map.merge(state.config, config_updates)
    new_state = %{state | config: new_config}
    Logger.info("Cache performance monitor configuration updated")
    {:reply, :ok, new_state}
  end

  @impl GenServer
  def handle_call(:force_check, _from, state) do
    {check_results, new_state} = perform_performance_check(state)
    {:reply, check_results, new_state}
  end

  @impl GenServer
  def handle_call(:get_recommendations, _from, state) do
    recommendations = generate_recommendations(state)
    {:reply, recommendations, state}
  end

  @impl GenServer
  def handle_info(:monitor_performance, state) do
    if state.monitoring_active do
      {_check_results, new_state} = perform_performance_check(state)
      schedule_monitoring(state.config.monitoring_interval)
      {:noreply, new_state}
    else
      {:noreply, state}
    end
  end

  # Private functions

  defp schedule_monitoring(interval) do
    Process.send_after(self(), :monitor_performance, interval)
  end

  defp perform_performance_check(state) do
    timestamp = System.monotonic_time(:millisecond)
    metrics = Metrics.get_metrics()

    # Analyze performance metrics
    performance_data = %{
      timestamp: timestamp,
      hit_ratio: metrics.hit_ratio,
      average_response_time: metrics.average_operation_time,
      memory_usage: get_memory_usage_percentage(metrics.memory_usage),
      eviction_rate: calculate_eviction_rate(metrics),
      total_operations: metrics.total_operations
    }

    # Determine performance status
    status = determine_performance_status(performance_data, state.config)

    # Check for alerts
    alerts = check_for_alerts(performance_data, state.config, state.alerts)

    # Update performance history
    new_history =
      update_performance_history(
        performance_data,
        state.performance_history,
        state.config.trend_analysis_window
      )

    # Generate recommendations
    recommendations =
      generate_recommendations_from_data(performance_data, new_history, state.config)

    # Log performance changes
    if status != state.current_status do
      Logger.info("Cache performance status changed from #{state.current_status} to #{status}",
        previous_status: state.current_status,
        new_status: status,
        hit_ratio: Float.round(performance_data.hit_ratio * 100, 1),
        response_time_ms: Float.round(performance_data.average_response_time, 1),
        memory_usage_mb: Float.round(performance_data.memory_usage / (1024 * 1024), 1),
        eviction_rate: Float.round(performance_data.eviction_rate * 100, 1),
        active_alerts: Map.keys(alerts)
      )
    end

    new_state = %{
      state
      | current_status: status,
        last_check: timestamp,
        performance_history: new_history,
        alerts: alerts,
        recommendations: recommendations
    }

    check_results = %{
      status: status,
      metrics: performance_data,
      alerts: Map.keys(alerts),
      recommendations: recommendations
    }

    {check_results, new_state}
  end

  defp determine_performance_status(performance_data, config) do
    cond do
      performance_data.hit_ratio < config.hit_ratio_threshold * 0.8 or
        performance_data.average_response_time > config.response_time_threshold * 2 or
          performance_data.memory_usage > config.memory_usage_threshold * 1.2 ->
        :critical

      performance_data.hit_ratio < config.hit_ratio_threshold or
        performance_data.average_response_time > config.response_time_threshold or
          performance_data.memory_usage > config.memory_usage_threshold ->
        :degraded

      true ->
        :healthy
    end
  end

  defp check_for_alerts(performance_data, config, existing_alerts) do
    current_time = System.system_time(:millisecond)

    # Check each alert type
    alerts = %{}

    # Hit ratio alert
    alerts =
      if performance_data.hit_ratio < config.hit_ratio_threshold do
        check_and_add_alert_with_value(
          alerts,
          existing_alerts,
          :hit_ratio_low,
          current_time,
          config.alert_cooldown,
          performance_data.hit_ratio,
          config.hit_ratio_threshold,
          "Hit ratio: #{Float.round(performance_data.hit_ratio * 100, 1)}% (threshold: #{Float.round(config.hit_ratio_threshold * 100, 1)}%)"
        )
      else
        Map.delete(alerts, :hit_ratio_low)
      end

    # Response time alert
    alerts =
      if performance_data.average_response_time > config.response_time_threshold do
        check_and_add_alert_with_value(
          alerts,
          existing_alerts,
          :response_time_high,
          current_time,
          config.alert_cooldown,
          performance_data.average_response_time,
          config.response_time_threshold,
          "Response time: #{Float.round(performance_data.average_response_time, 1)}ms (threshold: #{config.response_time_threshold}ms)"
        )
      else
        Map.delete(alerts, :response_time_high)
      end

    # Memory usage alert
    alerts =
      if performance_data.memory_usage > config.memory_usage_threshold do
        memory_mb = Float.round(performance_data.memory_usage / (1024 * 1024), 1)
        threshold_mb = Float.round(config.memory_usage_threshold / (1024 * 1024), 1)

        check_and_add_alert_with_value(
          alerts,
          existing_alerts,
          :memory_usage_high,
          current_time,
          config.alert_cooldown,
          performance_data.memory_usage,
          config.memory_usage_threshold,
          "Memory usage: #{memory_mb}MB (threshold: #{threshold_mb}MB)"
        )
      else
        Map.delete(alerts, :memory_usage_high)
      end

    # Eviction rate alert
    alerts =
      if performance_data.eviction_rate > config.eviction_rate_threshold do
        check_and_add_alert_with_value(
          alerts,
          existing_alerts,
          :eviction_rate_high,
          current_time,
          config.alert_cooldown,
          performance_data.eviction_rate,
          config.eviction_rate_threshold,
          "Eviction rate: #{Float.round(performance_data.eviction_rate * 100, 1)}% (threshold: #{Float.round(config.eviction_rate_threshold * 100, 1)}%)"
        )
      else
        Map.delete(alerts, :eviction_rate_high)
      end

    alerts
  end

  defp check_and_add_alert_with_value(
         alerts,
         existing_alerts,
         alert_type,
         current_time,
         cooldown,
         _current_value,
         _threshold,
         message
       ) do
    case Map.get(existing_alerts, alert_type) do
      nil ->
        # New alert
        Logger.warning("Cache performance alert: #{alert_type} - #{message}")
        Map.put(alerts, alert_type, current_time)

      last_alert_time ->
        # Existing alert - check cooldown
        if current_time - last_alert_time > cooldown do
          time_since = div(current_time - last_alert_time, 1000)

          Logger.warning(
            "Cache performance alert (repeated after #{time_since}s): #{alert_type} - #{message}"
          )

          Map.put(alerts, alert_type, current_time)
        else
          Map.put(alerts, alert_type, last_alert_time)
        end
    end
  end

  defp update_performance_history(performance_data, history, max_size) do
    new_history = [performance_data | history]
    Enum.take(new_history, max_size)
  end

  defp generate_recommendations(state) do
    if length(state.performance_history) > 0 do
      latest_data = hd(state.performance_history)
      generate_recommendations_from_data(latest_data, state.performance_history, state.config)
    else
      []
    end
  end

  defp generate_recommendations_from_data(performance_data, history, config) do
    recommendations = []

    # Hit ratio recommendations
    recommendations =
      if performance_data.hit_ratio < config.hit_ratio_threshold do
        [
          %{
            type: :hit_ratio_improvement,
            priority: :high,
            description:
              "Cache hit ratio is below threshold (#{Float.round(performance_data.hit_ratio * 100, 2)}%)",
            actions: [
              "Consider increasing cache TTL for frequently accessed data",
              "Implement cache warming strategies",
              "Review cache eviction policies"
            ]
          }
          | recommendations
        ]
      else
        recommendations
      end

    # Response time recommendations
    recommendations =
      if performance_data.average_response_time > config.response_time_threshold do
        [
          %{
            type: :response_time_improvement,
            priority: :medium,
            description:
              "Average response time is above threshold (#{Float.round(performance_data.average_response_time, 2)}ms)",
            actions: [
              "Optimize cache key generation",
              "Consider cache partitioning for better performance",
              "Review cache adapter configuration"
            ]
          }
          | recommendations
        ]
      else
        recommendations
      end

    # Memory usage recommendations
    recommendations =
      if performance_data.memory_usage > config.memory_usage_threshold do
        [
          %{
            type: :memory_optimization,
            priority: :medium,
            description:
              "Memory usage is above threshold (#{Float.round(performance_data.memory_usage * 100, 2)}%)",
            actions: [
              "Implement more aggressive cache eviction",
              "Reduce cache size limits",
              "Consider data compression for cached values"
            ]
          }
          | recommendations
        ]
      else
        recommendations
      end

    # Trend-based recommendations
    recommendations =
      if length(history) >= 3 do
        trend_recommendations = analyze_trends(history)
        recommendations ++ trend_recommendations
      else
        recommendations
      end

    recommendations
  end

  defp analyze_trends(history) do
    # Analyze hit ratio trend
    hit_ratios = Enum.map(history, & &1.hit_ratio)

    if declining_trend?(hit_ratios) do
      [
        %{
          type: :trend_analysis,
          priority: :medium,
          description: "Cache hit ratio is showing a declining trend",
          actions: [
            "Investigate recent changes that might affect cache effectiveness",
            "Review cache invalidation patterns",
            "Consider adjusting cache warming strategies"
          ]
        }
      ]
    else
      []
    end
  end

  defp declining_trend?(values) when length(values) < 3, do: false

  defp declining_trend?(values) do
    # Simple trend detection: check if recent values are generally decreasing
    recent_values = Enum.take(values, 3)
    [newest, middle, oldest] = recent_values

    newest < middle and middle < oldest
  end

  defp get_memory_usage_percentage(memory_usage) do
    # This is a simplified calculation - in a real implementation,
    # you'd want to get actual memory limits and calculate percentage
    case memory_usage do
      %{memory_usage: usage} when is_number(usage) ->
        # Assume a reasonable memory limit for percentage calculation
        # 100MB as example limit
        usage / (100 * 1024 * 1024)

      _ ->
        0.0
    end
  end

  defp calculate_eviction_rate(metrics) do
    total_operations = metrics.total_operations
    evictions = metrics.evictions

    if total_operations > 0 do
      evictions / total_operations
    else
      0.0
    end
  end

  defp build_status_response(state) do
    %{
      status: state.current_status,
      monitoring_active: state.monitoring_active,
      last_check: state.last_check,
      active_alerts: Map.keys(state.alerts),
      recommendation_count: length(state.recommendations)
    }
  end

  defp build_performance_report(state) do
    %{
      status: state.current_status,
      monitoring_active: state.monitoring_active,
      last_check: state.last_check,
      configuration: state.config,
      performance_history: state.performance_history,
      active_alerts: state.alerts,
      recommendations: state.recommendations,
      trend_analysis:
        if(length(state.performance_history) >= 3,
          do: analyze_trends(state.performance_history),
          else: []
        )
    }
  end
end
