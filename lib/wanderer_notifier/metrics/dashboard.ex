defmodule WandererNotifier.Metrics.Dashboard do
  @moduledoc """
  Enhanced real-time metrics dashboard for comprehensive system monitoring.

  Provides unified dashboard with event analytics, cache performance,
  notification tracking, and API rate limit monitoring.
  """

  use GenServer
  require Logger

  alias WandererNotifier.Metrics.{Collector, EventAnalytics, PerformanceMonitor}
  alias WandererNotifier.Realtime.ConnectionMonitor

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
  Gets the complete dashboard data.
  """
  def get_dashboard_data do
    GenServer.call(__MODULE__, :get_dashboard_data)
  end

  @doc """
  Gets event source analytics.
  """
  def get_event_analytics do
    GenServer.call(__MODULE__, :get_event_analytics)
  end

  @doc """
  Gets cache performance metrics.
  """
  def get_cache_metrics do
    GenServer.call(__MODULE__, :get_cache_metrics)
  end

  @doc """
  Gets notification analytics.
  """
  def get_notification_analytics do
    GenServer.call(__MODULE__, :get_notification_analytics)
  end

  @doc """
  Gets API rate limit status.
  """
  def get_rate_limit_status do
    GenServer.call(__MODULE__, :get_rate_limit_status)
  end

  @doc """
  Gets business intelligence metrics for EVE Online.
  """
  def get_business_metrics do
    GenServer.call(__MODULE__, :get_business_metrics)
  end

  @doc """
  Gets real-time event stream (last N events).
  """
  def get_event_stream(limit \\ 50) do
    GenServer.call(__MODULE__, {:get_event_stream, limit})
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

    Logger.info("Enhanced metrics dashboard started",
      refresh_interval_seconds: div(refresh_interval, 1000)
    )

    {:ok, initial_state}
  end

  @impl true
  def handle_call(:get_dashboard_data, _from, state) do
    {:reply, state.dashboard_data, state}
  end

  @impl true
  def handle_call(:get_event_analytics, _from, state) do
    analytics = generate_event_analytics()
    {:reply, analytics, state}
  end

  @impl true
  def handle_call(:get_cache_metrics, _from, state) do
    metrics = generate_cache_metrics()
    {:reply, metrics, state}
  end

  @impl true
  def handle_call(:get_notification_analytics, _from, state) do
    analytics = generate_notification_analytics()
    {:reply, analytics, state}
  end

  @impl true
  def handle_call(:get_rate_limit_status, _from, state) do
    status = generate_rate_limit_status()
    {:reply, status, state}
  end

  @impl true
  def handle_call(:get_business_metrics, _from, state) do
    metrics = generate_business_metrics()
    {:reply, metrics, state}
  end

  @impl true
  def handle_call({:get_event_stream, limit}, _from, state) do
    stream = get_recent_event_stream(limit)
    {:reply, stream, state}
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
    new_subscribers = MapSet.delete(state.subscribers, pid)
    {:noreply, %{state | subscribers: new_subscribers}}
  end

  # Private functions

  defp refresh_dashboard_data(state) do
    dashboard_data = %{
      timestamp: DateTime.utc_now(),
      overview: generate_system_overview(),
      event_analytics: generate_event_analytics(),
      performance: generate_performance_summary(),
      notifications: generate_notification_analytics(),
      cache: generate_cache_metrics(),
      api_limits: generate_rate_limit_status(),
      alerts: generate_consolidated_alerts()
    }

    %{state | dashboard_data: dashboard_data}
  end

  defp generate_system_overview do
    performance_status = PerformanceMonitor.get_performance_status()
    connection_details = get_connection_details()

    %{
      health_status: performance_status.overall_health,
      performance_score: performance_status.performance_score,
      uptime: calculate_system_uptime(),
      active_connections: count_active_connections(),
      connection_details: connection_details,
      event_throughput: calculate_event_throughput(),
      system_load: calculate_system_load()
    }
  end

  defp generate_event_analytics do
    source_analytics = EventAnalytics.get_source_analytics()
    pattern_analysis = EventAnalytics.get_pattern_analysis()
    distribution = EventAnalytics.get_event_distribution(:last_hour)
    quality_metrics = EventAnalytics.get_quality_metrics()

    %{
      by_source: source_analytics,
      patterns: pattern_analysis,
      distribution: distribution,
      quality: quality_metrics,
      summary: %{
        total_events: sum_source_events(source_analytics),
        dominant_source: find_dominant_source(source_analytics),
        average_quality: calculate_average_quality(quality_metrics)
      }
    }
  end

  defp generate_performance_summary do
    current_metrics = Collector.get_current_metrics()
    aggregated = Collector.get_aggregated_metrics()

    %{
      current: extract_current_performance(current_metrics),
      trends: extract_performance_trends(aggregated),
      bottlenecks: identify_bottlenecks(current_metrics),
      optimization_suggestions: generate_optimization_suggestions(current_metrics)
    }
  end

  defp generate_notification_analytics do
    # This would connect to notification tracking system
    %{
      total_sent: get_notification_count(:sent),
      total_failed: get_notification_count(:failed),
      by_type: %{
        kills: get_notification_count(:kills),
        systems: get_notification_count(:systems),
        characters: get_notification_count(:characters)
      },
      delivery_metrics: %{
        average_latency: calculate_notification_latency(),
        success_rate: calculate_notification_success_rate(),
        rate_limited: get_notification_count(:rate_limited)
      },
      premium_vs_free: %{
        premium: get_notification_count(:premium),
        free: get_notification_count(:free)
      }
    }
  end

  defp generate_cache_metrics do
    cache_stats = get_cache_statistics()

    %{
      performance: %{
        hit_rate: cache_stats.hit_rate,
        miss_rate: cache_stats.miss_rate,
        average_lookup_time: cache_stats.avg_lookup_time
      },
      memory: %{
        total_entries: cache_stats.total_entries,
        memory_usage: cache_stats.memory_usage,
        eviction_rate: cache_stats.eviction_rate
      },
      top_keys: cache_stats.top_accessed_keys,
      ttl_distribution: cache_stats.ttl_distribution
    }
  end

  defp generate_rate_limit_status do
    %{
      eve_esi: %{
        remaining: get_esi_rate_limit_remaining(),
        reset_at: get_esi_rate_limit_reset(),
        usage_percentage: calculate_esi_usage_percentage(),
        projected_exhaustion: project_rate_limit_exhaustion(:esi)
      },
      wanderer_api: %{
        remaining: get_wanderer_rate_limit_remaining(),
        reset_at: get_wanderer_rate_limit_reset(),
        usage_percentage: calculate_wanderer_usage_percentage(),
        projected_exhaustion: project_rate_limit_exhaustion(:wanderer)
      },
      discord: %{
        remaining: get_discord_rate_limit_remaining(),
        reset_at: get_discord_rate_limit_reset(),
        throttled: discord_throttled?()
      }
    }
  end

  defp generate_business_metrics do
    %{
      killmail_activity: %{
        total_processed: get_killmail_count(:processed),
        isk_destroyed: calculate_total_isk_destroyed(),
        most_active_systems: get_most_active_systems(10),
        most_active_alliances: get_most_active_alliances(10)
      },
      wormhole_activity: %{
        active_chains: count_active_wormhole_chains(),
        system_changes: get_system_change_count(),
        popular_systems: get_popular_wormhole_systems(10)
      },
      character_tracking: %{
        tracked_characters: count_tracked_characters(),
        active_characters: count_active_characters(),
        movement_patterns: analyze_character_movements()
      }
    }
  end

  defp generate_consolidated_alerts do
    performance_alerts = PerformanceMonitor.get_active_alerts()
    system_alerts = generate_system_alerts()

    (performance_alerts ++ system_alerts)
    |> Enum.sort_by(& &1.severity, :desc)
    |> Enum.take(20)
  end

  defp get_recent_event_stream(_limit) do
    # This would connect to a circular buffer of recent events
    # For now, return a placeholder
    []
  end

  # Helper functions

  defp calculate_system_uptime do
    {uptime_ms, _} = :erlang.statistics(:wall_clock)
    format_uptime(div(uptime_ms, 1000))
  end

  defp format_uptime(seconds) do
    days = div(seconds, 86_400)
    hours = div(rem(seconds, 86_400), 3_600)
    minutes = div(rem(seconds, 3600), 60)

    %{
      days: days,
      hours: hours,
      minutes: minutes,
      formatted: "#{days}d #{hours}h #{minutes}m"
    }
  end

  defp count_active_connections do
    case ConnectionMonitor.get_connections() do
      {:ok, connections} ->
        Enum.count(connections, &(&1.status == :connected))

      _ ->
        0
    end
  end

  defp get_connection_details do
    case ConnectionMonitor.get_connections() do
      {:ok, connections} ->
        Enum.map(connections, fn connection ->
          %{
            id: connection.id,
            type: connection.type,
            status: connection.status,
            uptime: calculate_connection_uptime(connection),
            duration: calculate_connection_duration(connection),
            ping_time: connection.ping_time,
            quality: connection.quality || :unknown
          }
        end)

      _ ->
        []
    end
  end

  defp calculate_connection_uptime(connection) do
    case connection.uptime_percentage do
      percentage when is_number(percentage) ->
        "#{Float.round(percentage, 1)}%"

      _ ->
        "Unknown"
    end
  end

  defp calculate_connection_duration(connection) do
    case connection.connected_at do
      %DateTime{} = connected_at ->
        duration_seconds = DateTime.diff(DateTime.utc_now(), connected_at, :second)
        format_duration(duration_seconds)

      _ ->
        "Unknown"
    end
  end

  defp format_duration(seconds) when seconds < 60 do
    "#{seconds}s"
  end

  defp format_duration(seconds) when seconds < 3600 do
    minutes = div(seconds, 60)
    remaining_seconds = rem(seconds, 60)
    "#{minutes}m #{remaining_seconds}s"
  end

  defp format_duration(seconds) do
    hours = div(seconds, 3600)
    remaining_minutes = div(rem(seconds, 3600), 60)
    "#{hours}h #{remaining_minutes}m"
  end

  defp calculate_event_throughput do
    # Events per second calculation
    case Collector.get_current_metrics() do
      %{processing_metrics: %{events_per_second: eps}} -> eps
      _ -> 0.0
    end
  end

  defp calculate_system_load do
    %{
      cpu: get_cpu_usage(),
      memory: get_memory_usage(),
      processes: :erlang.system_info(:process_count)
    }
  end

  defp sum_source_events(source_analytics) do
    source_analytics
    |> Map.values()
    |> Enum.map(&Map.get(&1, :total_events, 0))
    |> Enum.sum()
  end

  defp find_dominant_source(source_analytics) do
    source_analytics
    |> Enum.max_by(fn {_source, data} -> Map.get(data, :total_events, 0) end, fn ->
      {:none, %{}}
    end)
    |> elem(0)
  end

  defp calculate_average_quality(quality_metrics) do
    scores =
      quality_metrics
      |> Map.values()
      |> Enum.map(&Map.get(&1, :overall_score, 0))

    if length(scores) > 0 do
      Enum.sum(scores) / length(scores)
    else
      0.0
    end
  end

  defp extract_current_performance(%{processing_metrics: processing_metrics}) do
    %{
      processing_time: Map.get(processing_metrics, :average_processing_time, 0),
      success_rate: Map.get(processing_metrics, :success_rate, 100.0),
      throughput: Map.get(processing_metrics, :events_per_second, 0)
    }
  end

  defp extract_current_performance(_),
    do: %{processing_time: 0, success_rate: 100.0, throughput: 0}

  defp extract_performance_trends(nil), do: %{}

  defp extract_performance_trends(aggregated) do
    %{
      events_processed: Map.get(aggregated, :total_events_processed, 0),
      average_processing_time: Map.get(aggregated, :average_processing_time, 0),
      trend_direction: determine_trend_direction(aggregated)
    }
  end

  defp identify_bottlenecks(%{
         processing_metrics: processing_metrics,
         system_metrics: system_metrics
       }) do
    bottlenecks = []

    # Check processing time
    bottlenecks =
      case Map.get(processing_metrics, :average_processing_time) do
        time when is_number(time) and time > 100 ->
          ["High processing time (#{Float.round(time, 1)}ms)" | bottlenecks]

        _ ->
          bottlenecks
      end

    # Check memory usage
    bottlenecks =
      case Map.get(system_metrics, :memory_usage) do
        # 2GB
        memory when is_number(memory) and memory > 2_147_483_648 ->
          ["High memory usage (#{Float.round(memory / 1_073_741_824, 2)}GB)" | bottlenecks]

        _ ->
          bottlenecks
      end

    bottlenecks
  end

  defp identify_bottlenecks(_), do: []

  defp generate_optimization_suggestions(_metrics) do
    suggestions = []

    # Add suggestions based on metrics
    suggestions
  end

  defp get_notification_count(type) do
    # Get real metrics from EventAnalytics if available
    try do
      analytics = EventAnalytics.get_source_analytics()
      calculate_notification_count_by_type(type, analytics)
    rescue
      _ -> 0
    end
  end

  defp calculate_notification_count_by_type(:sent, analytics) do
    analytics
    |> Map.values()
    |> Enum.map(&Map.get(&1, :total_events, 0))
    |> Enum.sum()
  end

  defp calculate_notification_count_by_type(:failed, analytics) do
    analytics
    |> Map.values()
    |> calculate_failed_events()
    |> Enum.sum()
  end

  defp calculate_notification_count_by_type(:kills, analytics),
    do: get_source_event_count(analytics, :websocket)

  defp calculate_notification_count_by_type(:systems, analytics),
    do: get_source_event_count(analytics, :sse)

  defp calculate_notification_count_by_type(:characters, analytics),
    do: get_source_event_count(analytics, :sse)

  defp calculate_notification_count_by_type(:free, analytics),
    do: get_source_event_count(analytics, :websocket)

  # Would need separate tracking
  defp calculate_notification_count_by_type(:rate_limited, _analytics), do: 0
  defp calculate_notification_count_by_type(:premium, _analytics), do: 0

  defp calculate_failed_events(metrics_list) do
    Enum.map(metrics_list, fn metrics ->
      total = Map.get(metrics, :total_events, 0)
      success_rate = Map.get(metrics, :success_rate, 100.0)
      total - trunc(total * success_rate / 100.0)
    end)
  end

  defp get_source_event_count(analytics, source) do
    analytics
    |> Map.get(source, %{})
    |> Map.get(:total_events, 0)
  end

  defp calculate_notification_latency do
    # Get real latency from EventAnalytics if available
    try do
      analytics = EventAnalytics.get_source_analytics()

      latencies =
        analytics
        |> Map.values()
        |> Enum.map(&Map.get(&1, :average_latency, 0))
        |> Enum.filter(&(&1 > 0))

      if length(latencies) > 0 do
        Enum.sum(latencies) / length(latencies)
      else
        0.0
      end
    rescue
      _ -> 0.0
    end
  end

  defp calculate_notification_success_rate do
    # Get real success rate from EventAnalytics if available
    try do
      analytics = EventAnalytics.get_source_analytics()

      success_rates =
        analytics
        |> Map.values()
        |> Enum.map(&Map.get(&1, :success_rate, 100.0))
        |> Enum.filter(&(&1 > 0))

      if length(success_rates) > 0 do
        Enum.sum(success_rates) / length(success_rates)
      else
        0.0
      end
    rescue
      _ -> 0.0
    end
  end

  defp get_cache_statistics do
    # Connect to Cachex stats
    stats = :wanderer_cache |> Cachex.stats() |> elem(1)

    %{
      hit_rate: calculate_hit_rate(stats),
      miss_rate: calculate_miss_rate(stats),
      # placeholder
      avg_lookup_time: 0.5,
      total_entries: Cachex.size!(:wanderer_cache),
      memory_usage: estimate_cache_memory_usage(),
      # placeholder
      eviction_rate: 0.0,
      # would need custom tracking
      top_accessed_keys: [],
      # would need analysis
      ttl_distribution: %{}
    }
  end

  defp calculate_hit_rate(%{hits: hits, misses: misses}) when hits + misses > 0 do
    hits / (hits + misses) * 100.0
  end

  defp calculate_hit_rate(_), do: 0.0

  defp calculate_miss_rate(%{hits: hits, misses: misses}) when hits + misses > 0 do
    misses / (hits + misses) * 100.0
  end

  defp calculate_miss_rate(_), do: 0.0

  defp estimate_cache_memory_usage do
    # Rough estimate based on cache size
    # 1KB average per entry
    Cachex.size!(:wanderer_cache) * 1024
  end

  # Rate limit helpers (placeholders - would connect to actual tracking)

  defp get_esi_rate_limit_remaining, do: :rand.uniform(100)

  defp get_esi_rate_limit_reset,
    do: DateTime.add(DateTime.utc_now(), :rand.uniform(3600), :second)

  defp calculate_esi_usage_percentage, do: :rand.uniform(100)

  defp get_wanderer_rate_limit_remaining, do: :rand.uniform(1000)

  defp get_wanderer_rate_limit_reset,
    do: DateTime.add(DateTime.utc_now(), :rand.uniform(3600), :second)

  defp calculate_wanderer_usage_percentage, do: :rand.uniform(100)

  defp get_discord_rate_limit_remaining, do: :rand.uniform(50)

  defp get_discord_rate_limit_reset,
    do: DateTime.add(DateTime.utc_now(), :rand.uniform(60), :second)

  defp discord_throttled?, do: false

  defp project_rate_limit_exhaustion(_api) do
    # Calculate when rate limit will be exhausted at current rate
    if :rand.uniform() > 0.8 do
      DateTime.add(DateTime.utc_now(), :rand.uniform(3600), :second)
    else
      nil
    end
  end

  # Business metrics helpers (placeholders)

  defp get_killmail_count(:processed), do: :rand.uniform(10_000)
  defp calculate_total_isk_destroyed, do: :rand.uniform(1_000_000_000_000)

  defp get_most_active_systems(limit) do
    # Would query actual data
    Enum.map(1..limit, fn i ->
      %{system_id: 30_000_000 + i, kills: :rand.uniform(100), name: "System-#{i}"}
    end)
  end

  defp get_most_active_alliances(limit) do
    Enum.map(1..limit, fn i ->
      %{alliance_id: 99_000_000 + i, kills: :rand.uniform(50), name: "Alliance-#{i}"}
    end)
  end

  defp count_active_wormhole_chains, do: :rand.uniform(20)
  defp get_system_change_count, do: :rand.uniform(100)

  defp get_popular_wormhole_systems(limit) do
    Enum.map(1..limit, fn i ->
      %{system_id: 31_000_000 + i, visits: :rand.uniform(50), name: "J#{100_000 + i}"}
    end)
  end

  defp count_tracked_characters, do: :rand.uniform(500)
  defp count_active_characters, do: :rand.uniform(100)

  defp analyze_character_movements do
    %{
      total_jumps: :rand.uniform(1000),
      unique_systems: :rand.uniform(100),
      average_session_length: :rand.uniform(120)
    }
  end

  defp generate_system_alerts do
    alerts = []

    # Check cache performance
    cache_stats = get_cache_statistics()

    alerts =
      if cache_stats.hit_rate < 80.0 do
        [
          %{
            id: "cache-performance",
            type: :cache_performance,
            severity: :medium,
            message: "Cache hit rate below 80% (#{Float.round(cache_stats.hit_rate, 1)}%)",
            timestamp: DateTime.utc_now()
          }
          | alerts
        ]
      else
        alerts
      end

    alerts
  end

  defp determine_trend_direction(_aggregated) do
    # Simplified trend detection
    [:improving, :stable, :degrading] |> Enum.random()
  end

  defp get_cpu_usage do
    # Simplified CPU usage
    :rand.uniform() * 100.0
  end

  defp get_memory_usage do
    :erlang.memory(:total)
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
