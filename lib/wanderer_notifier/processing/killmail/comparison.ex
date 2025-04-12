defmodule WandererNotifier.Processing.Killmail.Comparison do
  @moduledoc """
  Compares killmail data between our database and zKillboard.

  @deprecated Please use WandererNotifier.Killmail.Utilities.Comparison instead

  This module is deprecated and will be removed in a future release.
  All functionality has been moved to WandererNotifier.Killmail.Utilities.Comparison.
  """

  require Logger
  alias WandererNotifier.Killmail.Utilities.Comparison, as: NewComparison

  # EVE Online type IDs
  # Structure category
  @structure_category_id 65
  # Capsule (pod) type ID
  @pod_type_id 670

  import Ash.Query

  alias WandererNotifier.Api.ESI.Service, as: ESIService
  alias WandererNotifier.Api.ZKill.Client, as: ZKillClient
  alias WandererNotifier.Data.Cache.Keys, as: CacheKeys
  alias WandererNotifier.Data.Cache.Repository, as: CacheRepo
  alias WandererNotifier.Logger.Logger, as: AppLogger
  alias WandererNotifier.Resources.{Api, Killmail, TrackedCharacter}
  alias WandererNotifier.Resources.KillHistoryService

  # Note: ZKillboard API no longer supports direct date filtering via startTime/endTime parameters.
  # Instead, we fetch all recent kills for a character and filter them in memory.
  # This approach was implemented after discovering that the API's date filtering was removed.

  @doc """
  Compares killmails between our database and zKillboard for a given character and timespan.

  @deprecated Please use WandererNotifier.Killmail.Utilities.Comparison.compare_killmails/3 instead
  """
  def compare_killmails(character_id, start_date, end_date) do
    Logger.warning("Using deprecated Comparison.compare_killmails/3, please update your code")
    NewComparison.compare_killmails(character_id, start_date, end_date)
  end

  @doc """
  Analyzes specific killmails that are missing from our database.

  @deprecated Please use WandererNotifier.Killmail.Utilities.Comparison.analyze_missing_kills/2 instead
  """
  def analyze_missing_kills(character_id, kill_ids) when is_list(kill_ids) do
    Logger.warning("Using deprecated Comparison.analyze_missing_kills/2, please update your code")
    NewComparison.analyze_missing_kills(character_id, kill_ids)
  end

  @doc """
  Compare killmails for a character from the last 24 hours against our database.

  @deprecated Please use WandererNotifier.Killmail.Utilities.Comparison.compare_recent_killmails/1 instead
  """
  def compare_recent_killmails(character_id) when is_integer(character_id) do
    Logger.warning(
      "Using deprecated Comparison.compare_recent_killmails/1, please update your code"
    )

    NewComparison.compare_recent_killmails(character_id)
  end

  @doc """
  Generates and caches comparison data for a specific time range.

  @deprecated Please use WandererNotifier.Killmail.Utilities.Comparison.generate_and_cache_comparison_data/3 instead
  """
  def generate_and_cache_comparison_data(cache_type, start_datetime, end_datetime) do
    Logger.warning(
      "Using deprecated Comparison.generate_and_cache_comparison_data/3, please update your code"
    )

    NewComparison.generate_and_cache_comparison_data(cache_type, start_datetime, end_datetime)
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
    AppLogger.processor_info("Generating character breakdowns", %{
      character_count: length(characters),
      start_datetime: DateTime.to_iso8601(start_datetime),
      end_datetime: DateTime.to_iso8601(end_datetime)
    })

    # Process each character with controlled concurrency (max 2 concurrent requests)
    # This helps prevent overwhelming the ZKillboard API
    characters
    |> Task.async_stream(
      fn character -> process_character_breakdown(character, start_datetime, end_datetime) end,
      max_concurrency: 2,
      timeout: 60_000
    )
    |> Enum.filter(fn
      {:ok, result} when not is_nil(result) -> true
      _ -> false
    end)
    |> Enum.map(fn {:ok, result} -> result end)
  end

  # Process a single character for breakdown
  defp process_character_breakdown(character, start_datetime, end_datetime) do
    character_id = extract_character_id(character)
    character_name = extract_character_name(character)

    AppLogger.processor_debug("Processing character breakdown", %{
      character_id: character_id,
      character_name: character_name
    })

    # Skip if no character_id
    if is_nil(character_id) do
      log_invalid_character(character)
      nil
    else
      get_character_breakdown(character_id, character_name, start_datetime, end_datetime)
    end
  end

  # Log when skipping an invalid character
  defp log_invalid_character(character) do
    AppLogger.processor_warn("Skipping character with invalid ID", %{
      character: inspect(character)
    })
  end

  # Get character breakdown with rate limiting
  defp get_character_breakdown(character_id, character_name, start_datetime, end_datetime) do
    # Add a small delay between characters to further reduce API load
    # even with low concurrency
    Process.sleep(500)

    case get_character_comparison(character_id, character_name, start_datetime, end_datetime) do
      {:ok, comparison_data} -> comparison_data
      _ -> nil
    end
  end

  # Private functions

  defp get_our_kills(character_id) do
    query =
      Killmail
      |> filter(related_character_id == ^character_id)

    case Api.read(query) do
      {:ok, kills} -> kills
      _ -> []
    end
  end

  defp fetch_our_kills(character_id, start_date, end_date) do
    query =
      Killmail
      |> filter(related_character_id == ^character_id)
      |> filter(kill_time >= ^start_date)
      |> filter(kill_time <= ^end_date)

    case Api.read(query) do
      {:ok, kills} ->
        {:ok, kills}

      error ->
        AppLogger.processor_error("Error fetching our kills",
          error: inspect(error),
          character_id: character_id
        )

        error
    end
  end

  defp fetch_zkill_kills(character_id, start_date, end_date) do
    case ZKillClient.get_character_kills(character_id) do
      {:ok, kills} ->
        AppLogger.processor_info("ZKill data received", %{
          kill_count: length(kills)
        })

        process_kills(kills, start_date, end_date)

      error ->
        AppLogger.processor_error("Error fetching kills from ZKill", %{
          error: inspect(error),
          character_id: character_id
        })

        error
    end
  end

  # Process the kills to filter them by date and fetch ESI data if needed
  defp process_kills(kills, start_date, end_date) do
    # For each kill, check date first, then fetch ESI data only if needed
    filtered_kills =
      kills
      |> Task.async_stream(
        fn kill -> process_single_kill(kill, start_date, end_date) end,
        max_concurrency: 5,
        timeout: 30_000
      )
      |> Stream.filter(fn
        {:ok, {:ok, _kill}} -> true
        _ -> false
      end)
      |> Stream.map(fn {:ok, {:ok, kill}} -> kill end)
      |> Enum.to_list()

    {:ok, filtered_kills}
  end

  # Process a single kill, checking if it's in the date range
  defp process_single_kill(kill, start_date, end_date) do
    # First check if we have this kill cached
    cache_key = CacheKeys.esi_killmail(kill["killmail_id"])

    case CacheRepo.get(cache_key) do
      nil -> fetch_and_check_kill(kill, cache_key, start_date, end_date)
      esi_data -> check_cached_kill(kill, esi_data, start_date, end_date)
    end
  end

  # Fetch a kill from ESI and check if it's in the date range
  defp fetch_and_check_kill(kill, cache_key, start_date, end_date) do
    # Fetch from ESI if not in cache
    case ESIService.get_killmail(
           kill["killmail_id"],
           extract_hash(kill)
         ) do
      {:ok, esi_data} ->
        # Store in cache for future reference with 24h TTL
        CacheRepo.set(cache_key, esi_data, 86_400)
        check_kill_relevance(esi_data, start_date, end_date)

      _ ->
        false
    end
  end

  # Check if a kill from cache is in the date range
  defp check_cached_kill(_kill, esi_data, start_date, end_date) do
    check_kill_relevance(esi_data, start_date, end_date)
  end

  # Check if a kill is in the requested date range
  defp check_kill_relevance(kill, start_date, end_date) do
    case DateTime.from_iso8601(kill["killmail_time"]) do
      {:ok, kill_date, _} ->
        if DateTime.compare(kill_date, start_date) in [:gt, :eq] and
             DateTime.compare(kill_date, end_date) in [:lt, :eq] do
          {:ok, Map.merge(kill, %{killmail_time: DateTime.to_iso8601(kill_date)})}
        else
          :skip
        end

      error ->
        AppLogger.processor_error("Failed to parse kill time", %{
          kill_id: kill["killmail_id"],
          error: inspect(error)
        })

        :skip
    end
  end

  defp calculate_comparison_stats(our_kills, zkill_kills, missing_kills, extra_kills) do
    our_count = MapSet.size(our_kills)
    zkill_count = MapSet.size(zkill_kills)
    missing_count = MapSet.size(missing_kills)
    extra_count = MapSet.size(extra_kills)

    # Calculate percentage match
    max_kills = max(our_count, zkill_count)

    percentage_match =
      if max_kills > 0 do
        matching_kills = zkill_count - missing_count
        Float.round(matching_kills / max_kills * 100, 2)
      else
        100.0
      end

    # Generate analysis
    analysis = generate_analysis(our_count, zkill_count, missing_count, extra_count)

    %{
      total_difference: abs(our_count - zkill_count),
      percentage_match: percentage_match,
      analysis: analysis
    }
  end

  defp generate_analysis(our_count, zkill_count, missing_count, extra_count) do
    if perfect_match?(our_count, zkill_count, missing_count, extra_count) do
      "Perfect match - all kills are accounted for"
    else
      generate_mismatch_analysis(missing_count, extra_count)
    end
  end

  defp perfect_match?(our_count, zkill_count, missing_count, extra_count) do
    our_count == zkill_count and missing_count == 0 and extra_count == 0
  end

  defp generate_mismatch_analysis(missing_count, extra_count) do
    case {missing_count > 0, extra_count > 0} do
      {true, false} -> "Missing kills only - we're not capturing all kills"
      {false, true} -> "Extra kills only - we have kills that zKill doesn't"
      {true, true} -> "Both missing and extra kills - potential processing issues"
      _ -> "Unexpected state - needs investigation"
    end
  end

  defp analyze_kill_miss_reason(kill_data, character_id) do
    AppLogger.processor_debug("Analyzing kill", %{
      kill_id: kill_data["killmail_id"],
      character_id: character_id
    })

    # Log the full kill data structure for debugging
    log_kill_data(kill_data, character_id)

    # Get zkb data once for NPC check
    zkb_data = Map.get(kill_data, "zkb", %{})
    is_npc = Map.get(zkb_data, "npc", false) == true

    # Check each possible reason in order
    cond do
      old_kill?(kill_data) -> {:ok, :old_kill}
      is_npc -> {:ok, :npc_kill}
      structure_kill?(kill_data) -> {:ok, :structure_kill}
      pod_kill?(kill_data) -> {:ok, :pod_kill}
      not_in_attackers_or_victim?(kill_data, character_id) -> {:ok, :not_involved}
      true -> {:error, :unknown_reason}
    end
  end

  defp log_kill_data(kill_data, character_id) do
    AppLogger.processor_info("Full kill data for analysis", %{
      character_id: character_id,
      kill_id: kill_data["killmail_id"],
      kill_time: kill_data["killmail_time"],
      victim_data: extract_victim_data(kill_data),
      attackers: extract_attackers_data(kill_data),
      zkb_data: extract_hash(kill_data)
    })
  end

  defp extract_attackers_data(kill_data) do
    Enum.map(kill_data["attackers"] || [], fn attacker ->
      %{
        character_id: attacker["character_id"],
        ship_type_id: attacker["ship_type_id"]
      }
    end)
  end

  defp old_kill?(kill_data) do
    case kill_data["killmail_time"] do
      nil ->
        false

      time ->
        kill_time = DateTime.from_iso8601(time)
        cutoff_date = DateTime.add(DateTime.utc_now(), -30 * 24 * 3600, :second)

        case kill_time do
          {:ok, datetime, _} -> DateTime.compare(datetime, cutoff_date) == :lt
          _ -> false
        end
    end
  end

  defp structure_kill?(kill_data) do
    victim = Map.get(kill_data, "victim") || %{}
    Map.get(victim, "category_id") == @structure_category_id
  end

  defp pod_kill?(kill_data) do
    victim = Map.get(kill_data, "victim") || %{}
    Map.get(victim, "ship_type_id") == @pod_type_id
  end

  defp not_in_attackers_or_victim?(kill_data, character_id) do
    str_char_id = to_string(character_id)

    # Check victim
    victim = kill_data["victim"] || %{}
    victim_id = victim["character_id"]
    victim_match = to_string(victim_id) == str_char_id

    # Log victim details
    AppLogger.processor_debug("Victim tracking check", %{
      kill_id: kill_data["killmail_id"],
      victim_id: victim_id,
      character_id: character_id,
      match: victim_match
    })

    # Check attackers
    attackers = kill_data["attackers"] || []

    # Log each attacker check
    attacker_match =
      Enum.any?(attackers, fn attacker ->
        attacker_char_id = attacker["character_id"]
        str_attacker_id = if(attacker_char_id, do: to_string(attacker_char_id), else: nil)
        is_match = str_attacker_id == str_char_id

        AppLogger.processor_debug("Attacker tracking check", %{
          kill_id: kill_data["killmail_id"],
          attacker_id: attacker_char_id,
          character_id: character_id,
          match: is_match
        })

        is_match
      end)

    AppLogger.processor_debug("Final tracking determination", %{
      kill_id: kill_data["killmail_id"],
      character_id: character_id,
      victim_match: victim_match,
      attacker_match: attacker_match,
      total_attackers: length(attackers)
    })

    not (victim_match or attacker_match)
  end

  # Private helper to analyze differences between zkill and our kills
  defp analyze_kill_differences(zkill_kills, our_kill_map) do
    # Find missing kills (in zKill but not in our DB)
    missing_kills =
      zkill_kills
      |> Enum.filter(fn kill -> !Map.has_key?(our_kill_map, kill["killmail_id"]) end)
      |> Enum.map(fn kill -> kill["killmail_id"] end)

    # Find extra kills (in our DB but not in zKill)
    zkill_kill_ids = MapSet.new(zkill_kills, & &1["killmail_id"])

    extra_kills =
      our_kill_map
      |> Map.keys()
      |> Enum.filter(fn kill_id -> !MapSet.member?(zkill_kill_ids, kill_id) end)

    {missing_kills, extra_kills}
  end

  # Private helper to calculate match statistics
  defp calculate_match_stats(our_count, _zkill_count, missing_count, extra_count) do
    # Total unique kills across both sources
    total_unique = our_count + missing_count
    # Kills that match between sources
    matched = our_count - extra_count

    percentage_match =
      if total_unique > 0 do
        matched / total_unique * 100
      else
        100.0
      end

    analysis =
      cond do
        percentage_match == 100.0 ->
          "Perfect match between our database and zKillboard"

        percentage_match > 90.0 ->
          "Very good coverage, only a few kills missing"

        percentage_match > 75.0 ->
          "Good coverage but some kills are missing"

        percentage_match > 50.0 ->
          "Moderate coverage, significant number of kills missing"

        true ->
          "Poor coverage, most kills are missing"
      end

    {percentage_match, analysis}
  end

  # Helper functions for character data extraction

  # Extract character ID from character data
  defp extract_character_id(character) do
    extract_character_id_by_type(character)
  end

  # Handle different types of character data for ID extraction
  defp extract_character_id_by_type(character) when is_struct(character) do
    extract_id_from_struct(character)
  end

  defp extract_character_id_by_type(character) when is_map(character) do
    extract_id_from_map(character)
  end

  defp extract_character_id_by_type(character) when is_binary(character) do
    character
  end

  defp extract_character_id_by_type(character) when is_integer(character) do
    to_string(character)
  end

  defp extract_character_id_by_type(_) do
    nil
  end

  # Extract ID from a struct
  defp extract_id_from_struct(struct) do
    if Map.has_key?(struct, :character_id) do
      struct.character_id
    else
      nil
    end
  end

  # Extract ID from a map
  defp extract_id_from_map(map) do
    cond do
      Map.has_key?(map, "character_id") -> map["character_id"]
      Map.has_key?(map, :character_id) -> map.character_id
      true -> nil
    end
  end

  # Extract character name from character data
  defp extract_character_name(character) do
    extract_character_name_by_type(character)
  end

  # Handle different types of character data for name extraction
  defp extract_character_name_by_type(character) when is_struct(character) do
    extract_name_from_struct(character)
  end

  defp extract_character_name_by_type(character) when is_map(character) do
    extract_name_from_map(character)
  end

  defp extract_character_name_by_type(_) do
    "Unknown Character"
  end

  # Extract name from a struct
  defp extract_name_from_struct(struct) do
    cond do
      Map.has_key?(struct, :character_name) -> struct.character_name
      Map.has_key?(struct, :name) -> struct.name
      true -> "Unknown Character"
    end
  end

  # Extract name from a map
  defp extract_name_from_map(map) do
    cond do
      Map.has_key?(map, "character_name") -> map["character_name"]
      Map.has_key?(map, "name") -> map["name"]
      Map.has_key?(map, :character_name) -> map.character_name
      Map.has_key?(map, :name) -> map.name
      true -> "Unknown Character"
    end
  end

  # Get comparison data for a specific character
  defp get_character_comparison(character_id, character_name, start_datetime, end_datetime) do
    # Get comparison data for this character
    case compare_killmails(character_id, start_datetime, end_datetime) do
      {:ok, result} ->
        # Calculate missing percentage
        missing_percentage =
          if result.zkill_kills > 0 do
            length(result.missing_kills) / result.zkill_kills * 100
          else
            0.0
          end

        # Return character comparison data
        {:ok,
         %{
           character_id: character_id,
           character_name: character_name,
           our_kills: result.our_kills,
           zkill_kills: result.zkill_kills,
           missing_kills: result.missing_kills,
           missing_percentage: missing_percentage
         }}

      error ->
        error
    end
  end

  defp format_character_comparison(character_id, character_name, comparison_data) do
    %{
      character_id: character_id,
      character_name: character_name,
      our_kills: comparison_data.our_kills,
      zkill_kills: comparison_data.zkill_kills,
      missing_kills: comparison_data.missing_kills,
      missing_percentage:
        if comparison_data.zkill_kills > 0 do
          length(comparison_data.missing_kills) / comparison_data.zkill_kills * 100
        else
          0.0
        end
    }
  end

  defp generate_fresh_comparison(
         character_id,
         character_name,
         start_datetime,
         end_datetime,
         cache_type
       ) do
    AppLogger.processor_info("Generating fresh comparison", %{
      character_id: character_id,
      cache_type: cache_type
    })

    case get_character_comparison(character_id, character_name, start_datetime, end_datetime) do
      {:ok, comparison_data} = result ->
        # Store in historical tracking
        KillHistoryService.record_comparison(
          character_id,
          comparison_data,
          cache_type
        )

        result

      error ->
        AppLogger.processor_error("Error generating comparison", %{
          character_id: character_id,
          error: inspect(error)
        })

        nil
    end
  end

  # Calculate the total kills across all characters
  defp calculate_kill_totals(character_comparisons) do
    # Initialize totals
    totals = %{
      our_kills: 0,
      zkill_kills: 0,
      missing_kills: 0,
      extra_kills: 0
    }

    # Sum up totals from all character comparisons
    Enum.reduce(character_comparisons, totals, fn comparison, acc ->
      %{
        our_kills: acc.our_kills + Map.get(comparison, :our_kills, 0),
        zkill_kills: acc.zkill_kills + Map.get(comparison, :zkill_kills, 0),
        missing_kills: acc.missing_kills + length(Map.get(comparison, :missing_kills, [])),
        extra_kills: acc.extra_kills + length(Map.get(comparison, :extra_kills, []))
      }
    end)
  end

  # Calculate aggregate statistics for all characters
  defp calculate_comparison_aggregate(character_comparisons) do
    if Enum.empty?(character_comparisons) do
      %{
        percentage_match: 100.0,
        analysis: "No character data available"
      }
    else
      # Get total kills from all characters
      _total_our_kills = Enum.sum(Enum.map(character_comparisons, & &1.our_kills))
      total_zkill_kills = Enum.sum(Enum.map(character_comparisons, & &1.zkill_kills))

      # Calculate total missing kills
      total_missing_kills =
        Enum.reduce(character_comparisons, 0, fn comp, acc ->
          acc + length(Map.get(comp, :missing_kills, []))
        end)

      # Calculate match percentage
      percentage_match =
        if total_zkill_kills > 0 do
          (total_zkill_kills - total_missing_kills) / total_zkill_kills * 100
        else
          100.0
        end

      # Generate analysis based on percentage
      analysis =
        cond do
          percentage_match >= 95.0 -> "Excellent tracking coverage across all characters"
          percentage_match >= 85.0 -> "Very good tracking coverage"
          percentage_match >= 75.0 -> "Good tracking coverage"
          percentage_match >= 60.0 -> "Moderate tracking coverage"
          percentage_match >= 40.0 -> "Poor tracking coverage"
          true -> "Very poor tracking coverage"
        end

      %{
        percentage_match: Float.round(percentage_match, 2),
        analysis: analysis
      }
    end
  end

  # Fetch killmail details from ZKillboard
  defp fetch_kill_from_zkill(kill_id) do
    # Log the attempt
    AppLogger.processor_debug("Fetching kill from ZKillboard", kill_id: kill_id)

    # Try to get the kill from zKill
    case ZKillClient.get_single_killmail(kill_id) do
      {:ok, kill_data} ->
        {:ok, kill_data}

      error ->
        AppLogger.processor_error("Error fetching kill from ZKillboard", %{
          kill_id: kill_id,
          error: inspect(error)
        })

        error
    end
  end

  defp extract_hash(kill_data) do
    zkb_map = Map.get(kill_data, "zkb", %{})
    Map.get(zkb_map, "hash")
  end

  defp extract_victim_data(killmail) do
    victim = Map.get(killmail, "victim", %{})
    character_id = Map.get(victim, "character_id")
    corporation_id = Map.get(victim, "corporation_id")
    alliance_id = Map.get(victim, "alliance_id")
    ship_type_id = Map.get(victim, "ship_type_id")

    %{
      character_id: character_id,
      corporation_id: corporation_id,
      alliance_id: alliance_id,
      ship_type_id: ship_type_id
    }
  end
end
