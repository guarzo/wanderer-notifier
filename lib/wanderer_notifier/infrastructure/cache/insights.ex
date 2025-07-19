defmodule WandererNotifier.Infrastructure.Cache.Insights do
  @moduledoc """
  Cache insights and optimization recommendations system.

  This module provides advanced cache analysis, optimization recommendations,
  and actionable insights based on cache usage patterns and performance metrics.
  It integrates with the Analytics module to provide intelligence layer.

  ## Features

  - Cache health scoring system
  - Performance optimization recommendations
  - Capacity planning insights
  - Cost-benefit analysis for cache operations
  - Predictive analytics for cache performance
  - Automated optimization suggestions
  - Dashboard data formatting
  - Alert generation for cache issues

  ## Health Scoring

  The health scoring system evaluates cache performance across multiple dimensions:
  - **Hit Rate Score**: Based on cache hit/miss ratios
  - **Performance Score**: Based on response times and latency
  - **Efficiency Score**: Based on memory usage and utilization
  - **Reliability Score**: Based on error rates and stability
  - **Overall Health Score**: Weighted combination of all scores

  ## Usage

  ```elixir
  # Get cache health score
  health = WandererNotifier.Infrastructure.Cache.Insights.get_health_score()

  # Get optimization recommendations
  recommendations = WandererNotifier.Infrastructure.Cache.Insights.get_optimization_recommendations()

  # Get dashboard data
  dashboard = WandererNotifier.Infrastructure.Cache.Insights.get_dashboard_data()

  # Generate performance report
  report = WandererNotifier.Infrastructure.Cache.Insights.generate_performance_report()
  ```
  """

  require Logger

  alias WandererNotifier.Infrastructure.Cache.Analytics

  @type health_score :: %{
          overall_score: float(),
          hit_rate_score: float(),
          performance_score: float(),
          efficiency_score: float(),
          reliability_score: float(),
          grade: String.t(),
          recommendations: [String.t()]
        }

  @type optimization_recommendation :: %{
          type: atom(),
          priority: :low | :medium | :high | :critical,
          description: String.t(),
          impact: String.t(),
          implementation: String.t(),
          estimated_improvement: float()
        }

  @type dashboard_data :: %{
          summary: map(),
          charts: map(),
          alerts: [map()],
          recommendations: [optimization_recommendation()],
          health_score: health_score()
        }

  @type performance_report :: %{
          executive_summary: String.t(),
          key_metrics: map(),
          performance_analysis: map(),
          recommendations: [optimization_recommendation()],
          capacity_planning: map(),
          cost_analysis: map()
        }

  # Health scoring thresholds
  @health_thresholds %{
    excellent: 0.9,
    good: 0.8,
    fair: 0.7,
    poor: 0.6
  }

  # Performance benchmarks
  @performance_benchmarks %{
    optimal_hit_rate: 0.95,
    acceptable_hit_rate: 0.85,
    # milliseconds
    optimal_response_time: 5.0,
    acceptable_response_time: 20.0,
    optimal_memory_usage: 0.8,
    max_memory_usage: 0.95
  }

  @doc """
  Gets comprehensive cache health score.

  ## Returns
  Health score map with overall score and component scores
  """
  @spec get_health_score() :: health_score()
  def get_health_score do
    # Get current analytics data
    usage_report = Analytics.get_usage_report()
    efficiency_metrics = Analytics.get_efficiency_metrics()

    # Calculate component scores
    hit_rate_score = calculate_hit_rate_score(usage_report.hit_rate)
    performance_score = calculate_performance_score(usage_report.average_response_time)
    efficiency_score = calculate_efficiency_score(efficiency_metrics)
    reliability_score = calculate_reliability_score()

    # Calculate overall score (weighted average)
    overall_score =
      calculate_overall_score(
        hit_rate_score,
        performance_score,
        efficiency_score,
        reliability_score
      )

    # Determine grade
    grade = determine_grade(overall_score)

    # Generate health-based recommendations
    recommendations =
      generate_health_recommendations(
        overall_score,
        hit_rate_score,
        performance_score,
        efficiency_score,
        reliability_score
      )

    %{
      overall_score: overall_score,
      hit_rate_score: hit_rate_score,
      performance_score: performance_score,
      efficiency_score: efficiency_score,
      reliability_score: reliability_score,
      grade: grade,
      recommendations: recommendations
    }
  end

  @doc """
  Gets optimization recommendations based on current cache state.

  ## Returns
  List of optimization recommendations
  """
  @spec get_optimization_recommendations() :: [optimization_recommendation()]
  def get_optimization_recommendations do
    # Get analytics data
    usage_report = Analytics.get_usage_report()
    efficiency_metrics = Analytics.get_efficiency_metrics()
    patterns = Analytics.analyze_patterns()

    # Generate recommendations
    recommendations = []

    # Hit rate optimization
    recommendations = recommendations ++ analyze_hit_rate_optimization(usage_report)

    # Performance optimization
    recommendations = recommendations ++ analyze_performance_optimization(usage_report)

    # Memory optimization
    recommendations = recommendations ++ analyze_memory_optimization(efficiency_metrics)

    # Pattern-based optimization
    recommendations = recommendations ++ analyze_pattern_optimization(patterns)

    # Capacity planning
    recommendations = recommendations ++ analyze_capacity_planning(usage_report)

    # Sort by priority
    Enum.sort_by(recommendations, fn rec ->
      case rec.priority do
        :critical -> 0
        :high -> 1
        :medium -> 2
        :low -> 3
      end
    end)
  end

  @doc """
  Gets formatted dashboard data for UI display.

  ## Returns
  Dashboard data map
  """
  @spec get_dashboard_data() :: dashboard_data()
  def get_dashboard_data do
    # Get all necessary data
    usage_report = Analytics.get_usage_report()
    efficiency_metrics = Analytics.get_efficiency_metrics()
    patterns = Analytics.analyze_patterns()
    health_score = get_health_score()
    recommendations = get_optimization_recommendations()

    # Build summary
    summary = build_summary(usage_report, efficiency_metrics, health_score)

    # Build charts data
    charts = build_charts_data(usage_report, patterns)

    # Generate alerts
    alerts = generate_alerts(usage_report, efficiency_metrics, health_score)

    %{
      summary: summary,
      charts: charts,
      alerts: alerts,
      recommendations: recommendations,
      health_score: health_score
    }
  end

  @doc """
  Generates comprehensive performance report.

  ## Returns
  Performance report map
  """
  @spec generate_performance_report() :: performance_report()
  def generate_performance_report do
    # Get analytics data
    usage_report = Analytics.get_usage_report()
    efficiency_metrics = Analytics.get_efficiency_metrics()
    patterns = Analytics.analyze_patterns()
    health_score = get_health_score()
    recommendations = get_optimization_recommendations()

    # Build executive summary
    executive_summary = build_executive_summary(usage_report, health_score)

    # Build key metrics
    key_metrics = build_key_metrics(usage_report, efficiency_metrics)

    # Build performance analysis
    performance_analysis = build_performance_analysis(usage_report, patterns)

    # Build capacity planning
    capacity_planning = build_capacity_planning(usage_report, patterns)

    # Build cost analysis
    cost_analysis = build_cost_analysis(usage_report, efficiency_metrics)

    %{
      executive_summary: executive_summary,
      key_metrics: key_metrics,
      performance_analysis: performance_analysis,
      recommendations: recommendations,
      capacity_planning: capacity_planning,
      cost_analysis: cost_analysis
    }
  end

  @doc """
  Analyzes cache trends and predicts future performance.

  ## Parameters
  - time_range: Historical time range to analyze (default: 24 hours)

  ## Returns
  Trend analysis and predictions
  """
  @spec analyze_trends(integer()) :: map()
  def analyze_trends(time_range \\ 24 * 60 * 60 * 1000) do
    historical_data = Analytics.get_historical_data(time_range)

    if length(historical_data.historical_data) > 0 do
      # Analyze trends
      hit_rate_trend = analyze_hit_rate_trend(historical_data.historical_data)
      performance_trend = analyze_performance_trend(historical_data.historical_data)
      usage_trend = analyze_usage_trend(historical_data.historical_data)

      # Generate predictions
      predictions = generate_performance_predictions(historical_data.historical_data)

      %{
        time_range: time_range,
        data_points: historical_data.data_points,
        hit_rate_trend: hit_rate_trend,
        performance_trend: performance_trend,
        usage_trend: usage_trend,
        predictions: predictions
      }
    else
      %{
        time_range: time_range,
        data_points: 0,
        hit_rate_trend: :insufficient_data,
        performance_trend: :insufficient_data,
        usage_trend: :insufficient_data,
        predictions: %{}
      }
    end
  end

  @doc """
  Generates alerts based on cache performance thresholds.

  ## Returns
  List of alerts
  """
  @spec get_alerts() :: [map()]
  def get_alerts do
    usage_report = Analytics.get_usage_report()
    efficiency_metrics = Analytics.get_efficiency_metrics()
    health_score = get_health_score()

    generate_alerts(usage_report, efficiency_metrics, health_score)
  end

  # Private functions

  defp calculate_hit_rate_score(hit_rate) do
    cond do
      hit_rate >= @performance_benchmarks.optimal_hit_rate -> 1.0
      hit_rate >= @performance_benchmarks.acceptable_hit_rate -> 0.8
      hit_rate >= 0.5 -> 0.6
      true -> 0.3
    end
  end

  defp calculate_performance_score(avg_response_time) do
    cond do
      avg_response_time <= @performance_benchmarks.optimal_response_time -> 1.0
      avg_response_time <= @performance_benchmarks.acceptable_response_time -> 0.8
      avg_response_time <= 50.0 -> 0.6
      true -> 0.3
    end
  end

  defp calculate_efficiency_score(efficiency_metrics) do
    efficiency_metrics.optimization_score
  end

  defp calculate_reliability_score do
    # In a real implementation, this would analyze error rates and stability
    # For now, return a good default score
    0.9
  end

  defp calculate_overall_score(
         hit_rate_score,
         performance_score,
         efficiency_score,
         reliability_score
       ) do
    # Weighted average: hit rate (30%), performance (25%), efficiency (25%), reliability (20%)
    hit_rate_score * 0.3 + performance_score * 0.25 + efficiency_score * 0.25 +
      reliability_score * 0.2
  end

  defp determine_grade(score) do
    cond do
      score >= @health_thresholds.excellent -> "A"
      score >= @health_thresholds.good -> "B"
      score >= @health_thresholds.fair -> "C"
      score >= @health_thresholds.poor -> "D"
      true -> "F"
    end
  end

  defp generate_health_recommendations(
         overall_score,
         _hit_rate_score,
         performance_score,
         efficiency_score,
         reliability_score
       ) do
    recommendations = []

    # Cache warming has been removed - cache is populated on-demand

    # Performance recommendations
    recommendations =
      if performance_score < 0.8 do
        ["Optimize cache access patterns to reduce response times" | recommendations]
      else
        recommendations
      end

    # Efficiency recommendations
    recommendations =
      if efficiency_score < 0.8 do
        ["Review cache size and eviction policies for better efficiency" | recommendations]
      else
        recommendations
      end

    # Reliability recommendations
    recommendations =
      if reliability_score < 0.8 do
        ["Monitor cache stability and error rates" | recommendations]
      else
        recommendations
      end

    # Overall recommendations
    recommendations =
      if overall_score < 0.7 do
        ["Consider comprehensive cache architecture review" | recommendations]
      else
        recommendations
      end

    recommendations
  end

  defp analyze_hit_rate_optimization(usage_report) do
    recommendations = []

    recommendations =
      if usage_report.hit_rate < @performance_benchmarks.acceptable_hit_rate do
        [
          %{
            type: :hit_rate,
            priority: :high,
            description:
              "Hit rate is below acceptable threshold (#{Float.round(usage_report.hit_rate * 100, 1)}%)",
            impact: "Poor hit rate increases response times and external API calls",
            implementation: "Cache is populated on-demand (warming removed)",
            estimated_improvement: 0.15
          }
          | recommendations
        ]
      else
        recommendations
      end

    # Data type specific recommendations
    Enum.reduce(usage_report.data_type_breakdown, recommendations, fn {type, stats}, acc ->
      if stats.hit_rate < 0.8 do
        [
          %{
            type: :hit_rate,
            priority: :medium,
            description:
              "#{type} data has low hit rate (#{Float.round(stats.hit_rate * 100, 1)}%)",
            impact: "Poor hit rate for #{type} data affects user experience",
            implementation: "#{type} cache populated on-demand (warming removed)",
            estimated_improvement: 0.10
          }
          | acc
        ]
      else
        acc
      end
    end)
  end

  defp analyze_performance_optimization(usage_report) do
    recommendations = []

    recommendations =
      if usage_report.average_response_time > @performance_benchmarks.acceptable_response_time do
        [
          %{
            type: :performance,
            priority: :high,
            description:
              "Average response time is high (#{Float.round(usage_report.average_response_time, 1)}ms)",
            impact: "High response times affect application performance",
            implementation: "Optimize cache access patterns and consider cache clustering",
            estimated_improvement: 0.20
          }
          | recommendations
        ]
      else
        recommendations
      end

    recommendations
  end

  defp analyze_memory_optimization(efficiency_metrics) do
    recommendations = []

    recommendations =
      if efficiency_metrics.memory_efficiency < 0.8 do
        [
          %{
            type: :memory,
            priority: :medium,
            description:
              "Memory efficiency is suboptimal (#{Float.round(efficiency_metrics.memory_efficiency * 100, 1)}%)",
            impact: "Poor memory usage may lead to performance degradation",
            implementation: "Review cache size limits and implement proper eviction policies",
            estimated_improvement: 0.15
          }
          | recommendations
        ]
      else
        recommendations
      end

    recommendations
  end

  defp analyze_pattern_optimization(patterns) do
    recommendations = []

    # Hotspot optimization
    recommendations =
      if length(patterns.hotspots) > 10 do
        [
          %{
            type: :hotspots,
            priority: :medium,
            description: "High number of cache hotspots detected (#{length(patterns.hotspots)})",
            impact: "Hotspots may indicate uneven cache distribution",
            implementation: "Consider cache partitioning or load balancing",
            estimated_improvement: 0.10
          }
          | recommendations
        ]
      else
        recommendations
      end

    # Cold key optimization
    recommendations =
      if length(patterns.cold_keys) > 50 do
        [
          %{
            type: :cold_keys,
            priority: :low,
            description: "Many cold keys detected (#{length(patterns.cold_keys)})",
            impact: "Cold keys consume memory without providing value",
            implementation: "Implement TTL policies for rarely accessed keys",
            estimated_improvement: 0.05
          }
          | recommendations
        ]
      else
        recommendations
      end

    recommendations
  end

  defp analyze_capacity_planning(usage_report) do
    recommendations = []

    recommendations =
      if usage_report.total_operations > 100_000 do
        [
          %{
            type: :capacity,
            priority: :medium,
            description:
              "High cache usage detected (#{usage_report.total_operations} operations)",
            impact: "High usage may require capacity planning",
            implementation: "Monitor growth trends and plan for scaling",
            estimated_improvement: 0.0
          }
          | recommendations
        ]
      else
        recommendations
      end

    recommendations
  end

  defp build_summary(usage_report, efficiency_metrics, health_score) do
    %{
      total_operations: usage_report.total_operations,
      hit_rate: usage_report.hit_rate,
      average_response_time: usage_report.average_response_time,
      efficiency_score: efficiency_metrics.optimization_score,
      health_grade: health_score.grade,
      peak_usage_time: usage_report.peak_usage_time
    }
  end

  defp build_charts_data(usage_report, patterns) do
    %{
      hit_rate_chart: %{
        hits: usage_report.hit_count,
        misses: usage_report.miss_count,
        hit_rate: usage_report.hit_rate
      },
      data_type_chart: usage_report.data_type_breakdown,
      hotspots_chart: Enum.take(patterns.hotspots, 10),
      temporal_chart: patterns.temporal_patterns
    }
  end

  defp generate_alerts(usage_report, efficiency_metrics, health_score) do
    alerts = []

    # Critical hit rate alert
    alerts =
      if usage_report.hit_rate < 0.5 do
        [
          %{
            type: :critical,
            title: "Critical Hit Rate",
            message:
              "Cache hit rate is critically low (#{Float.round(usage_report.hit_rate * 100, 1)}%)",
            action: "Immediate optimization required"
          }
          | alerts
        ]
      else
        alerts
      end

    # High response time alert
    alerts =
      if usage_report.average_response_time > 100.0 do
        [
          %{
            type: :warning,
            title: "High Response Time",
            message:
              "Average response time is high (#{Float.round(usage_report.average_response_time, 1)}ms)",
            action: "Review cache performance"
          }
          | alerts
        ]
      else
        alerts
      end

    # Low efficiency alert
    alerts =
      if efficiency_metrics.optimization_score < 0.6 do
        [
          %{
            type: :warning,
            title: "Low Cache Efficiency",
            message:
              "Cache efficiency is below optimal (#{Float.round(efficiency_metrics.optimization_score * 100, 1)}%)",
            action: "Review cache configuration"
          }
          | alerts
        ]
      else
        alerts
      end

    # Poor health score alert
    alerts =
      if health_score.overall_score < 0.6 do
        [
          %{
            type: :error,
            title: "Poor Cache Health",
            message: "Overall cache health is poor (Grade: #{health_score.grade})",
            action: "Comprehensive review needed"
          }
          | alerts
        ]
      else
        alerts
      end

    alerts
  end

  defp build_executive_summary(usage_report, health_score) do
    """
    Cache Performance Executive Summary

    Overall Health: #{health_score.grade} (#{Float.round(health_score.overall_score * 100, 1)}%)

    Key Metrics:
    - Total Operations: #{usage_report.total_operations}
    - Hit Rate: #{Float.round(usage_report.hit_rate * 100, 1)}%
    - Average Response Time: #{Float.round(usage_report.average_response_time, 1)}ms

    The cache system is performing at #{health_score.grade} level with #{Float.round(health_score.overall_score * 100, 1)}% efficiency.
    #{if health_score.overall_score < 0.8, do: "Optimization opportunities exist to improve performance.", else: "System is operating within acceptable parameters."}
    """
  end

  defp build_key_metrics(usage_report, efficiency_metrics) do
    %{
      operations: %{
        total: usage_report.total_operations,
        hits: usage_report.hit_count,
        misses: usage_report.miss_count
      },
      performance: %{
        hit_rate: usage_report.hit_rate,
        average_response_time: usage_report.average_response_time,
        efficiency_score: efficiency_metrics.optimization_score
      },
      breakdown: usage_report.data_type_breakdown
    }
  end

  defp build_performance_analysis(usage_report, patterns) do
    %{
      hit_rate_analysis: analyze_hit_rate_performance(usage_report),
      response_time_analysis: analyze_response_time_performance(usage_report),
      pattern_analysis: analyze_usage_patterns_performance(patterns)
    }
  end

  defp build_capacity_planning(usage_report, patterns) do
    %{
      current_usage: usage_report.total_operations,
      growth_projection: project_growth(usage_report),
      capacity_recommendations: generate_capacity_recommendations(usage_report, patterns)
    }
  end

  defp build_cost_analysis(usage_report, efficiency_metrics) do
    %{
      efficiency_cost: calculate_efficiency_cost(efficiency_metrics),
      miss_cost: calculate_miss_cost(usage_report),
      optimization_savings: calculate_optimization_savings(usage_report, efficiency_metrics)
    }
  end

  defp analyze_hit_rate_trend(historical_data) do
    hit_rates = Enum.map(historical_data, & &1.hit_rate)

    if length(hit_rates) > 1 do
      first_rate = List.first(hit_rates)
      last_rate = List.last(hit_rates)

      cond do
        last_rate > first_rate + 0.05 -> :improving
        last_rate < first_rate - 0.05 -> :declining
        true -> :stable
      end
    else
      :insufficient_data
    end
  end

  defp analyze_performance_trend(historical_data) do
    response_times = Enum.map(historical_data, & &1.avg_response_time)

    if length(response_times) > 1 do
      first_time = List.first(response_times)
      last_time = List.last(response_times)

      cond do
        last_time < first_time * 0.9 -> :improving
        last_time > first_time * 1.1 -> :declining
        true -> :stable
      end
    else
      :insufficient_data
    end
  end

  defp analyze_usage_trend(historical_data) do
    operation_counts = Enum.map(historical_data, & &1.operations_count)

    if length(operation_counts) > 1 do
      first_count = List.first(operation_counts)
      last_count = List.last(operation_counts)

      cond do
        last_count > first_count * 1.2 -> :increasing
        last_count < first_count * 0.8 -> :decreasing
        true -> :stable
      end
    else
      :insufficient_data
    end
  end

  defp generate_performance_predictions(historical_data) do
    if length(historical_data) > 10 do
      # Simple linear prediction based on recent trend
      recent_data = Enum.take(historical_data, 5)

      avg_hit_rate =
        recent_data
        |> Enum.map(& &1.hit_rate)
        |> Enum.sum()
        |> Kernel./(length(recent_data))

      avg_response_time =
        recent_data
        |> Enum.map(& &1.avg_response_time)
        |> Enum.sum()
        |> Kernel./(length(recent_data))

      %{
        predicted_hit_rate: avg_hit_rate,
        predicted_response_time: avg_response_time,
        confidence: 0.7
      }
    else
      %{
        predicted_hit_rate: nil,
        predicted_response_time: nil,
        confidence: 0.0
      }
    end
  end

  # Simplified helper functions for analysis
  defp analyze_hit_rate_performance(usage_report) do
    "Hit rate of #{Float.round(usage_report.hit_rate * 100, 1)}% indicates #{if usage_report.hit_rate > 0.8, do: "good", else: "suboptimal"} cache performance."
  end

  defp analyze_response_time_performance(usage_report) do
    "Average response time of #{Float.round(usage_report.average_response_time, 1)}ms is #{if usage_report.average_response_time < 20, do: "acceptable", else: "high"}."
  end

  defp analyze_usage_patterns_performance(patterns) do
    "Cache shows #{length(patterns.hotspots)} hotspots and #{length(patterns.cold_keys)} cold keys."
  end

  defp project_growth(usage_report) do
    # Simple growth projection
    %{
      daily_ops: usage_report.total_operations,
      projected_weekly: usage_report.total_operations * 7,
      projected_monthly: usage_report.total_operations * 30
    }
  end

  defp generate_capacity_recommendations(usage_report, patterns) do
    recommendations = []

    recommendations =
      if usage_report.total_operations > 50_000 do
        ["Consider horizontal scaling for high operation volume" | recommendations]
      else
        recommendations
      end

    recommendations =
      if length(patterns.hotspots) > 20 do
        ["Consider cache partitioning for hotspot distribution" | recommendations]
      else
        recommendations
      end

    recommendations
  end

  defp calculate_efficiency_cost(efficiency_metrics) do
    # Simplified cost calculation
    efficiency_loss = 1.0 - efficiency_metrics.optimization_score

    %{
      efficiency_loss_percentage: efficiency_loss * 100,
      estimated_cost_impact: "#{Float.round(efficiency_loss * 100, 1)}% efficiency loss"
    }
  end

  defp calculate_miss_cost(usage_report) do
    %{
      miss_count: usage_report.miss_count,
      miss_rate: usage_report.miss_rate,
      estimated_api_calls: usage_report.miss_count
    }
  end

  defp calculate_optimization_savings(_usage_report, efficiency_metrics) do
    potential_improvement = 1.0 - efficiency_metrics.optimization_score

    %{
      potential_hit_rate_improvement: potential_improvement * 0.5,
      potential_response_time_reduction: potential_improvement * 0.3,
      estimated_savings:
        "#{Float.round(potential_improvement * 100, 1)}% performance improvement possible"
    }
  end
end
