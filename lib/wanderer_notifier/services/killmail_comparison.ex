defmodule WandererNotifier.Services.KillmailComparison do
  @moduledoc """
  Service for comparing killmail data between our database and zKillboard.
  Helps identify discrepancies in kill tracking.

  Note: This module is deprecated and will be removed in a future version.
  Please use WandererNotifier.Processing.Killmail.Comparison instead.
  """

  alias WandererNotifier.Core.Logger, as: AppLogger
  alias WandererNotifier.Processing.Killmail.Comparison

  @doc """
  Compares killmails between our database and zKillboard for a given character and timespan.

  ## Parameters
    - character_id: The character ID to compare
    - start_date: Start date for comparison (DateTime)
    - end_date: End date for comparison (DateTime)

  ## Returns
    {:ok, %{
      our_kills: integer,
      zkill_kills: integer,
      missing_kills: [integer],
      extra_kills: [integer],
      comparison: %{
        total_difference: integer,
        percentage_match: float,
        analysis: String.t()
      }
    }}
  """
  def compare_killmails(character_id, start_date, end_date) do
    AppLogger.processor_debug(
      "KillmailComparison.compare_killmails is deprecated, please use WandererNotifier.Processing.Killmail.Comparison.compare_killmails/3 instead"
    )

    Comparison.compare_killmails(character_id, start_date, end_date)
  end

  @doc """
  Analyzes specific killmails that are missing from our database.
  Helps identify patterns in what we're missing.

  ## Parameters
    - character_id: The character ID to analyze
    - kill_ids: List of killmail IDs to analyze

  ## Returns
    {:ok, analysis_results}
  """
  def analyze_missing_kills(character_id, kill_ids) when is_list(kill_ids) do
    AppLogger.processor_debug(
      "KillmailComparison.analyze_missing_kills is deprecated, please use WandererNotifier.Processing.Killmail.Comparison.analyze_missing_kills/2 instead"
    )

    Comparison.analyze_missing_kills(character_id, kill_ids)
  end

  @doc """
  Compare killmails for a character from the last 24 hours against our database.
  Returns a map containing:
  - our_kills: number of kills in our database
  - zkill_kills: number of kills on zKillboard
  - missing_kills: list of kill IDs found on zKillboard but not in our database
  - extra_kills: list of kill IDs found in our database but not on zKillboard
  - comparison: statistics about the comparison
  """
  def compare_recent_killmails(character_id) when is_integer(character_id) do
    AppLogger.processor_debug(
      "KillmailComparison.compare_recent_killmails is deprecated, please use WandererNotifier.Processing.Killmail.Comparison.compare_recent_killmails/1 instead"
    )

    Comparison.compare_recent_killmails(character_id)
  end

  @doc """
  Generates and caches comparison data for a specific time range.
  Now with historical tracking support.

  ## Parameters
    - cache_type: The type of cache to generate (e.g., "1h", "4h", "12h", "24h", "7d")
    - start_datetime: The start of the time range
    - end_datetime: The end of the time range

  ## Returns
    - {:ok, comparison_data} on success
    - {:error, reason} on failure
  """
  @spec generate_and_cache_comparison_data(String.t(), DateTime.t(), DateTime.t()) ::
          {:ok, map()} | {:error, term()}
  def generate_and_cache_comparison_data(cache_type, start_datetime, end_datetime) do
    AppLogger.processor_debug(
      "KillmailComparison.generate_and_cache_comparison_data is deprecated, please use WandererNotifier.Processing.Killmail.Comparison.generate_and_cache_comparison_data/3 instead"
    )

    Comparison.generate_and_cache_comparison_data(cache_type, start_datetime, end_datetime)
  end

  @doc """
  Generates character breakdowns for comparison between our database and ZKillboard.

  ## Parameters
    - characters: List of character maps with character_id and character_name
    - start_datetime: The start of the time range
    - end_datetime: The end of the time range

  ## Returns
    - List of character comparison data
  """
  @spec generate_character_breakdowns(list(map()), DateTime.t(), DateTime.t()) :: list(map())
  def generate_character_breakdowns(characters, start_datetime, end_datetime) do
    AppLogger.processor_debug(
      "KillmailComparison.generate_character_breakdowns is deprecated, please use WandererNotifier.Processing.Killmail.Comparison.generate_character_breakdowns/3 instead"
    )

    Comparison.generate_character_breakdowns(characters, start_datetime, end_datetime)
  end
end
