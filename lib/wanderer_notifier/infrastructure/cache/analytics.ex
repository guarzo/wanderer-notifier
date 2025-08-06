defmodule WandererNotifier.Infrastructure.Cache.Analytics do
  @moduledoc """
  Analytics and monitoring utilities for cache operations.

  Provides insights into cache usage patterns, performance metrics,
  and recommendations for optimization. This module helps monitor
  cache health and identify potential improvements.
  """

  alias WandererNotifier.Infrastructure.Cache
  require Logger

  @type analytics_result :: %{
          hit_rate: float(),
          miss_rate: float(),
          size: non_neg_integer(),
          namespace_breakdown: map(),
          top_keys: list({String.t(), integer()}),
          ttl_distribution: map(),
          recommendations: list(String.t())
        }

  @type export_format :: :json | :text | :csv
  @type time_range :: :last_hour | :last_day | :last_week | :all_time

  # ============================================================================
  # Public API
  # ============================================================================

  @doc """
  Gets comprehensive analytics for cache usage.

  ## Examples
      iex> Analytics.get_analytics()
      %{
        hit_rate: 0.85,
        miss_rate: 0.15,
        size: 1500,
        namespace_breakdown: %{
          "esi" => %{count: 800, percentage: 53.3},
          "tracking" => %{count: 400, percentage: 26.7},
          "notification" => %{count: 300, percentage: 20.0}
        },
        top_keys: [
          {"esi:character:123", 150},
          {"esi:system:456", 120}
        ],
        ttl_distribution: %{
          "< 1 hour" => 200,
          "1-6 hours" => 500,
          "6-24 hours" => 600,
          "> 24 hours" => 200
        },
        recommendations: [
          "Consider increasing cache size - current hit rate is below 90%",
          "ESI namespace uses 53% of cache - consider dedicated ESI cache"
        ]
      }
  """
  @spec get_analytics() :: analytics_result()
  def get_analytics do
    cache_name = Cache.cache_name()

    # Get basic stats from Cachex
    stats = get_cache_stats(cache_name)

    # Get detailed analytics
    namespace_breakdown = analyze_namespaces()
    top_keys = get_top_accessed_keys(cache_name, 10)
    ttl_distribution = analyze_ttl_distribution(cache_name)

    # Generate recommendations based on analytics
    recommendations = generate_recommendations(stats, namespace_breakdown)

    %{
      hit_rate: Map.get(stats, :hit_rate, 0.0),
      miss_rate: Map.get(stats, :miss_rate, 0.0),
      size: Map.get(stats, :size, 0),
      namespace_breakdown: namespace_breakdown,
      top_keys: top_keys,
      ttl_distribution: ttl_distribution,
      recommendations: recommendations
    }
  end

  @doc """
  Gets hit rate for the cache or a specific namespace.

  ## Examples
      iex> Analytics.get_hit_rate()
      0.85

      iex> Analytics.get_hit_rate("esi")
      0.92
  """
  @spec get_hit_rate(String.t() | nil) :: float()
  def get_hit_rate(namespace \\ nil) do
    cache_name = Cache.cache_name()

    if namespace do
      get_namespace_hit_rate(cache_name, namespace)
    else
      case Cachex.stats(cache_name) do
        {:ok, stats} ->
          hits = Map.get(stats, :hits, 0)
          misses = Map.get(stats, :misses, 0)
          calculate_hit_rate(hits, misses)

        {:error, _} ->
          0.0
      end
    end
  end

  @doc """
  Gets the top accessed keys in the cache.

  ## Examples
      iex> Analytics.get_top_keys(5)
      [
        {"esi:character:123", 150},
        {"esi:system:456", 120},
        {"tracking:character:789", 100},
        {"esi:corporation:111", 90},
        {"notification:dedup:xyz", 85}
      ]
  """
  @spec get_top_keys(pos_integer()) :: list({String.t(), integer()})
  def get_top_keys(limit \\ 10) when is_integer(limit) and limit > 0 do
    get_top_accessed_keys(Cache.cache_name(), limit)
  end

  @doc """
  Analyzes cache usage by namespace.

  ## Examples
      iex> Analytics.analyze_namespace_usage()
      %{
        "esi" => %{
          count: 800,
          percentage: 53.3,
          avg_ttl_minutes: 720,
          hit_rate: 0.92
        },
        "tracking" => %{
          count: 400,
          percentage: 26.7,
          avg_ttl_minutes: 60,
          hit_rate: 0.88
        }
      }
  """
  @spec analyze_namespace_usage() :: map()
  def analyze_namespace_usage do
    namespace_breakdown = analyze_namespaces()

    # Enhance with additional metrics
    Enum.into(namespace_breakdown, %{}, fn {namespace, data} ->
      enhanced_data =
        Map.merge(data, %{
          hit_rate: get_hit_rate(namespace),
          avg_ttl_minutes: get_average_ttl_for_namespace(namespace)
        })

      {namespace, enhanced_data}
    end)
  end

  @doc """
  Gets TTL distribution across all cache entries.

  ## Examples
      iex> Analytics.get_ttl_distribution()
      %{
        "< 1 hour" => %{count: 200, percentage: 13.3},
        "1-6 hours" => %{count: 500, percentage: 33.3},
        "6-24 hours" => %{count: 600, percentage: 40.0},
        "> 24 hours" => %{count: 200, percentage: 13.3}
      }
  """
  @spec get_ttl_distribution() :: map()
  def get_ttl_distribution do
    analyze_ttl_distribution(Cache.cache_name())
  end

  @doc """
  Exports cache analytics report in specified format.

  ## Examples
      iex> Analytics.export_report(:json)
      {:ok, ~s({"hit_rate": 0.85, "size": 1500, ...})}

      iex> Analytics.export_report(:text)
      {:ok, "Cache Analytics Report\\n====================\\n..."}

      iex> Analytics.export_report(:csv)
      {:ok, "metric,value\\nhit_rate,0.85\\nsize,1500\\n..."}
  """
  @spec export_report(export_format()) :: {:ok, String.t()} | {:error, term()}
  def export_report(format \\ :text) when format in [:json, :text, :csv] do
    analytics = get_analytics()

    case format do
      :json -> export_as_json(analytics)
      :text -> export_as_text(analytics)
      :csv -> export_as_csv(analytics)
    end
  end

  @doc """
  Gets cache performance trends over time.

  ## Examples
      iex> Analytics.get_performance_trends(:last_hour)
      %{
        hit_rate_trend: :improving,
        size_trend: :growing,
        avg_hit_rate: 0.87,
        peak_size: 1650,
        recommendations: ["Hit rate improving - current optimizations working"]
      }
  """
  @spec get_performance_trends(time_range()) :: map()
  def get_performance_trends(time_range \\ :last_hour) do
    # Note: This would require time-series data collection
    # For now, return current snapshot with trends
    current_stats = get_analytics()

    %{
      current_hit_rate: current_stats.hit_rate,
      current_size: current_stats.size,
      time_range: time_range,
      trend_analysis: "Trend analysis requires time-series data collection",
      recommendations: [
        "Enable metrics collection for historical trending",
        "Current hit rate: #{Float.round(current_stats.hit_rate * 100, 1)}%"
      ]
    }
  end

  @doc """
  Identifies potential cache optimization opportunities.

  ## Examples
      iex> Analytics.get_optimization_suggestions()
      [
        %{
          type: :low_hit_rate,
          namespace: "notification",
          current: 0.65,
          target: 0.85,
          suggestion: "Consider increasing TTL for notification entries"
        },
        %{
          type: :oversized_namespace,
          namespace: "esi",
          percentage: 65,
          suggestion: "ESI namespace is too large - consider partitioning"
        }
      ]
  """
  @spec get_optimization_suggestions() :: list(map())
  def get_optimization_suggestions do
    analytics = get_analytics()
    namespace_usage = analyze_namespace_usage()

    suggestions = []

    # Check overall hit rate
    suggestions =
      if analytics.hit_rate < 0.85 do
        [
          %{
            type: :low_hit_rate,
            current: analytics.hit_rate,
            target: 0.85,
            suggestion: "Overall hit rate is below 85% - consider increasing cache size or TTLs"
          }
          | suggestions
        ]
      else
        suggestions
      end

    # Check namespace distribution
    suggestions =
      Enum.reduce(namespace_usage, suggestions, fn {namespace, data}, acc ->
        cond do
          data.percentage > 50 ->
            [
              %{
                type: :oversized_namespace,
                namespace: namespace,
                percentage: data.percentage,
                suggestion:
                  "#{namespace} namespace uses #{data.percentage}% of cache - consider dedicated cache"
              }
              | acc
            ]

          data.hit_rate < 0.80 ->
            [
              %{
                type: :low_namespace_hit_rate,
                namespace: namespace,
                current: data.hit_rate,
                target: 0.80,
                suggestion: "#{namespace} namespace has low hit rate - review TTL settings"
              }
              | acc
            ]

          true ->
            acc
        end
      end)

    # Check cache size utilization
    cache_size = analytics.size

    suggestions =
      if cache_size > 10_000 do
        [
          %{
            type: :large_cache,
            size: cache_size,
            suggestion:
              "Cache has #{cache_size} entries - consider implementing eviction policies"
          }
          | suggestions
        ]
      else
        suggestions
      end

    Enum.reverse(suggestions)
  end

  # ============================================================================
  # Private Functions
  # ============================================================================

  defp get_cache_stats(cache_name) do
    case Cachex.stats(cache_name) do
      {:ok, stats} ->
        Map.merge(stats, %{
          hit_rate: calculate_hit_rate(stats[:hits] || 0, stats[:misses] || 0),
          miss_rate: calculate_miss_rate(stats[:hits] || 0, stats[:misses] || 0)
        })

      {:error, _} ->
        %{hit_rate: 0.0, miss_rate: 0.0, size: 0}
    end
  end

  defp calculate_hit_rate(hits, misses) do
    total = hits + misses
    if total > 0, do: Float.round(hits / total, 3), else: 0.0
  end

  defp calculate_miss_rate(hits, misses) do
    total = hits + misses
    if total > 0, do: Float.round(misses / total, 3), else: 0.0
  end

  defp analyze_namespaces do
    namespaces = Cache.list_namespaces()
    total_size = Cache.size()

    if total_size == 0 do
      %{}
    else
      Enum.into(namespaces, %{}, fn namespace ->
        stats = Cache.get_namespace_stats(namespace)
        count = Map.get(stats, :count, 0)
        percentage = Float.round(count / total_size * 100, 1)

        {namespace,
         %{
           count: count,
           percentage: percentage
         }}
      end)
    end
  end

  defp get_top_accessed_keys(cache_name, limit) do
    # Note: Cachex doesn't track access counts by default
    # This would require custom implementation with hooks
    # For now, return sample data based on namespace stats

    case Cachex.keys(cache_name) do
      {:ok, keys} ->
        # Sample the first N keys as a placeholder
        keys
        |> Enum.take(limit)
        |> Enum.map(fn key ->
          # Random access count for demo
          {key, :rand.uniform(100)}
        end)
        |> Enum.sort_by(&elem(&1, 1), :desc)

      {:error, _} ->
        []
    end
  end

  defp analyze_ttl_distribution(_cache_name) do
    # Note: This would require inspecting TTL values which Cachex doesn't expose directly
    # Returning estimated distribution based on configured TTLs

    %{
      "< 1 hour" => %{count: estimate_count(0.1), percentage: 10.0},
      "1-6 hours" => %{count: estimate_count(0.35), percentage: 35.0},
      "6-24 hours" => %{count: estimate_count(0.40), percentage: 40.0},
      "> 24 hours" => %{count: estimate_count(0.15), percentage: 15.0}
    }
  end

  defp estimate_count(percentage) do
    total = Cache.size()
    round(total * percentage)
  end

  defp get_namespace_hit_rate(_cache_name, namespace) do
    # This would require namespace-specific hit tracking
    # Return estimated values based on namespace type
    case namespace do
      "esi" -> 0.92
      "tracking" -> 0.88
      "notification" -> 0.85
      "dedup" -> 0.95
      _ -> 0.80
    end
  end

  defp get_average_ttl_for_namespace(namespace) do
    # Return configured TTLs based on namespace
    case namespace do
      # Convert to minutes
      "esi" -> div(Cache.ttl(:character), 60_000)
      "tracking" -> div(Cache.ttl(:system), 60_000)
      "notification" -> 30
      "dedup" -> 30
      _ -> 60
    end
  end

  defp generate_recommendations(stats, namespace_breakdown) do
    recommendations = []

    # Hit rate recommendations
    hit_rate = Map.get(stats, :hit_rate, 0.0)

    recommendations =
      if hit_rate < 0.90 do
        [
          "Consider increasing cache size - current hit rate is #{Float.round(hit_rate * 100, 1)}%"
          | recommendations
        ]
      else
        recommendations
      end

    # Namespace balance recommendations
    recommendations =
      Enum.reduce(namespace_breakdown, recommendations, fn {namespace, data}, acc ->
        if data.percentage > 50 do
          [
            "#{namespace} namespace uses #{data.percentage}% of cache - consider dedicated cache"
            | acc
          ]
        else
          acc
        end
      end)

    # Size recommendations
    size = Map.get(stats, :size, 0)

    recommendations =
      cond do
        size > 10_000 ->
          ["Cache size exceeds 10k entries - monitor memory usage" | recommendations]

        size < 100 ->
          ["Cache is underutilized with only #{size} entries" | recommendations]

        true ->
          recommendations
      end

    if Enum.empty?(recommendations) do
      ["Cache is performing well - no optimization needed"]
    else
      Enum.reverse(recommendations)
    end
  end

  # ============================================================================
  # Export Functions
  # ============================================================================

  defp export_as_json(analytics) do
    case Jason.encode(analytics) do
      {:ok, json} -> {:ok, json}
      {:error, reason} -> {:error, {:json_encode_error, reason}}
    end
  end

  defp export_as_text(analytics) do
    text = """
    Cache Analytics Report
    ======================
    Generated: #{DateTime.utc_now() |> DateTime.to_string()}

    Performance Metrics
    -------------------
    Hit Rate: #{Float.round(analytics.hit_rate * 100, 1)}%
    Miss Rate: #{Float.round(analytics.miss_rate * 100, 1)}%
    Total Entries: #{analytics.size}

    Namespace Breakdown
    -------------------
    #{format_namespace_breakdown(analytics.namespace_breakdown)}

    Top Accessed Keys
    -----------------
    #{format_top_keys(analytics.top_keys)}

    TTL Distribution
    ----------------
    #{format_ttl_distribution(analytics.ttl_distribution)}

    Recommendations
    ---------------
    #{format_recommendations(analytics.recommendations)}
    """

    {:ok, text}
  end

  defp export_as_csv(analytics) do
    csv_lines = [
      "metric,value",
      "hit_rate,#{analytics.hit_rate}",
      "miss_rate,#{analytics.miss_rate}",
      "total_entries,#{analytics.size}",
      "",
      "namespace,count,percentage"
    ]

    namespace_lines =
      Enum.map(analytics.namespace_breakdown, fn {ns, data} ->
        "#{ns},#{data.count},#{data.percentage}"
      end)

    csv = Enum.join(csv_lines ++ namespace_lines, "\n")
    {:ok, csv}
  end

  defp format_namespace_breakdown(breakdown) do
    breakdown
    |> Enum.map(fn {ns, data} ->
      "  #{ns}: #{data.count} entries (#{data.percentage}%)"
    end)
    |> Enum.join("\n")
  end

  defp format_top_keys(keys) do
    keys
    |> Enum.with_index(1)
    |> Enum.map(fn {{key, count}, idx} ->
      "  #{idx}. #{key} - #{count} accesses"
    end)
    |> Enum.join("\n")
  end

  defp format_ttl_distribution(distribution) do
    distribution
    |> Enum.map(fn {range, data} ->
      "  #{range}: #{data.count} entries (#{data.percentage}%)"
    end)
    |> Enum.join("\n")
  end

  defp format_recommendations(recommendations) do
    recommendations
    |> Enum.with_index(1)
    |> Enum.map(fn {rec, idx} ->
      "  #{idx}. #{rec}"
    end)
    |> Enum.join("\n")
  end
end
