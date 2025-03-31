defmodule WandererNotifier.Services.KillTrackingHistory do
  @moduledoc """
  Service for managing historical kill tracking data.
  Provides functionality to store and retrieve historical kill comparison data.

  Note: This module is deprecated and will be removed in a future version.
  Please use WandererNotifier.Resources.KillHistoryService instead.
  """

  require Logger
  alias WandererNotifier.Core.Logger, as: AppLogger
  alias WandererNotifier.Resources.KillHistoryService

  @doc """
  Records a new comparison result in the history.
  """
  def record_comparison(character_id, comparison_result, time_range_type) do
    AppLogger.processor_debug(
      "WandererNotifier.Services.KillTrackingHistory.record_comparison is deprecated, please use WandererNotifier.Resources.KillHistoryService.record_comparison/3 instead"
    )

    KillHistoryService.record_comparison(character_id, comparison_result, time_range_type)
  end

  @doc """
  Gets the most recent comparison data for a character and time range.
  """
  def get_latest_comparison(character_id, time_range_type) do
    AppLogger.processor_debug(
      "WandererNotifier.Services.KillTrackingHistory.get_latest_comparison is deprecated, please use WandererNotifier.Resources.KillHistoryService.get_latest_comparison/2 instead"
    )

    KillHistoryService.get_latest_comparison(character_id, time_range_type)
  end

  @doc """
  Gets historical comparison data for trend analysis.
  """
  def get_historical_data(character_id, time_range_type, limit \\ 100) do
    AppLogger.processor_debug(
      "WandererNotifier.Services.KillTrackingHistory.get_historical_data is deprecated, please use WandererNotifier.Resources.KillHistoryService.get_historical_data/3 instead"
    )

    KillHistoryService.get_historical_data(character_id, time_range_type, limit)
  end

  @doc """
  Checks if we have recent enough data or need to refresh.
  """
  def needs_refresh?(character_id, time_range_type) do
    AppLogger.processor_debug(
      "WandererNotifier.Services.KillTrackingHistory.needs_refresh? is deprecated, please use WandererNotifier.Resources.KillHistoryService.needs_refresh?/2 instead"
    )

    KillHistoryService.needs_refresh?(character_id, time_range_type)
  end
end
