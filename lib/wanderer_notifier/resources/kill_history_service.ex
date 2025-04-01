defmodule WandererNotifier.Resources.KillHistoryService do
  @moduledoc """
  Service for managing historical kill tracking data.
  Provides functionality to store and retrieve historical kill comparison data.
  """

  require Logger
  alias WandererNotifier.Resources.Api
  alias WandererNotifier.Resources.KillTrackingHistory

  @doc """
  Records a new comparison result in the history.
  """
  def record_comparison(character_id, comparison_result, time_range_type) do
    our_kills = Map.get(comparison_result, :our_kills, 0)
    zkill_kills = Map.get(comparison_result, :zkill_kills, 0)
    missing_kills = Map.get(comparison_result, :missing_kills, [])

    Api.create(KillTrackingHistory, %{
      character_id: character_id,
      timestamp: DateTime.utc_now(),
      our_kills_count: our_kills,
      zkill_kills_count: zkill_kills,
      missing_kills: missing_kills,
      analysis_results: get_analysis_results(comparison_result),
      api_metrics: get_api_metrics(),
      time_range_type: time_range_type
    })
  end

  @doc """
  Gets the most recent comparison data for a character and time range.
  """
  def get_latest_comparison(character_id, time_range_type) do
    case KillTrackingHistory.get_latest_for_character(character_id, time_range_type) do
      {:ok, nil} -> {:error, :not_found}
      {:ok, record} -> {:ok, to_comparison_result(record)}
      error -> error
    end
  end

  @doc """
  Gets historical comparison data for trend analysis.
  """
  def get_historical_data(character_id, time_range_type, limit \\ 100) do
    case KillTrackingHistory.get_history_for_character(character_id, time_range_type, limit) do
      {:ok, records} -> {:ok, Enum.map(records, &to_trend_data/1)}
      error -> error
    end
  end

  @doc """
  Checks if we have recent enough data or need to refresh.
  """
  def needs_refresh?(character_id, time_range_type) do
    max_age = get_max_age_for_range(time_range_type)

    case get_latest_comparison(character_id, time_range_type) do
      {:ok, record} ->
        age_seconds = DateTime.diff(DateTime.utc_now(), record.timestamp)
        age_seconds > max_age

      _ ->
        true
    end
  end

  # Private functions

  defp get_analysis_results(comparison_result) do
    # Handle case where comparison key doesn't exist
    if Map.has_key?(comparison_result, :comparison) do
      %{
        total_difference: comparison_result.comparison.total_difference,
        percentage_match: comparison_result.comparison.percentage_match,
        analysis: comparison_result.comparison.analysis
      }
    else
      # Generate basic analysis from available data
      %{
        total_difference: 0,
        percentage_match: 100.0,
        analysis:
          if(comparison_result.zkill_kills == 0,
            do: "No kills found in time period",
            else: "Data comparison incomplete"
          )
      }
    end
  end

  defp get_api_metrics do
    %{
      zkb_response_time: get_zkb_response_time(),
      esi_response_time: get_esi_response_time(),
      cache_hit_rate: get_cache_hit_rate()
    }
  end

  defp to_comparison_result(record) do
    %{
      our_kills: record.our_kills_count,
      zkill_kills: record.zkill_kills_count,
      missing_kills: record.missing_kills || [],
      comparison: record.analysis_results,
      timestamp: record.timestamp,
      api_metrics: record.api_metrics
    }
  end

  defp to_trend_data(record) do
    %{
      timestamp: record.timestamp,
      our_kills: record.our_kills_count,
      zkill_kills: record.zkill_kills_count,
      missing_count: length(record.missing_kills || []),
      percentage_match: get_in(record.analysis_results || %{}, [:percentage_match])
    }
  end

  defp get_max_age_for_range(range_type) do
    case range_type do
      # 5 minutes
      "1h" -> 300
      # 10 minutes
      "4h" -> 600
      # 30 minutes
      "12h" -> 1800
      # 1 hour
      "24h" -> 3600
      # 2 hours
      "7d" -> 7200
      # default 30 minutes
      _ -> 1800
    end
  end

  # Placeholder functions for metrics - implement these based on your monitoring system
  defp get_zkb_response_time, do: 0
  defp get_esi_response_time, do: 0
  defp get_cache_hit_rate, do: 0.0
end
