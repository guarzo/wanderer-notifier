defmodule WandererNotifier.Services.KillmailComparison do
  @moduledoc """
  Service for comparing killmail data between our database and zKillboard.
  Helps identify discrepancies in kill tracking.
  """

  require Logger
  alias WandererNotifier.Api.ESI.Service, as: ESIService
  alias WandererNotifier.Data.Cache.Repository, as: CacheRepo
  alias WandererNotifier.Logger, as: AppLogger
  alias WandererNotifier.Resources.{Api, Killmail, TrackedCharacter}
  alias WandererNotifier.Services.{KillTrackingHistory, ZKillboardApi}
  import Ash.Query

  # Note: ZKillboard API no longer supports direct date filtering via startTime/endTime parameters.
  # Instead, we fetch all recent kills for a character and filter them in memory.
  # This approach was implemented after discovering that the API's date filtering was removed.

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
    AppLogger.processor_info("Starting killmail comparison", %{
      character_id: character_id,
      start_date: DateTime.to_iso8601(start_date),
      end_date: DateTime.to_iso8601(end_date)
    })

    with {:ok, our_kills} <- fetch_our_kills(character_id, start_date, end_date),
         {:ok, zkill_kills} <- fetch_zkill_kills(character_id, start_date, end_date) do
      our_kill_ids = MapSet.new(our_kills, & &1.killmail_id)
      zkill_kill_ids = MapSet.new(zkill_kills, & &1["killmail_id"])

      # Find kills we're missing (in zKill but not in our DB)
      missing_kills = MapSet.difference(zkill_kill_ids, our_kill_ids)

      # Find extra kills (in our DB but not in zKill)
      extra_kills = MapSet.difference(our_kill_ids, zkill_kill_ids)

      # Calculate statistics
      stats =
        calculate_comparison_stats(
          our_kill_ids,
          zkill_kill_ids,
          missing_kills,
          extra_kills
        )

      {:ok,
       %{
         our_kills: MapSet.size(our_kill_ids),
         zkill_kills: MapSet.size(zkill_kill_ids),
         missing_kills: MapSet.to_list(missing_kills),
         extra_kills: MapSet.to_list(extra_kills),
         comparison: stats
       }}
    end
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
    # Fetch detailed information about missing kills from zKillboard
    kills_info = Enum.map(kill_ids, fn kill_id -> analyze_single_kill(character_id, kill_id) end)

    # Group by reason and format for JSON
    grouped_analysis = group_kills_by_reason(kills_info)

    {:ok, grouped_analysis}
  end

  # Analyze a single kill to determine why it might be missing
  defp analyze_single_kill(character_id, kill_id) do
    case ZKillboardApi.get_killmail(kill_id) do
      {:ok, kill_data} ->
        log_zkb_data(kill_id, kill_data)
        process_kill_data(character_id, kill_id, kill_data)

      _ ->
        %{kill_id: kill_id, reason: :fetch_failed}
    end
  end

  # Log ZKB data for a kill
  defp log_zkb_data(kill_id, kill_data) do
    AppLogger.processor_info("ZKB Data", %{
      kill_id: kill_id,
      data: inspect(kill_data)
    })
  end

  # Process kill data from ZKB and ESI
  defp process_kill_data(character_id, kill_id, kill_data) do
    # Get the hash from ZKB data
    hash = get_in(kill_data, ["zkb", "hash"])

    # Fetch ESI data
    case ESIService.get_killmail(kill_id, hash) do
      {:ok, esi_data} ->
        process_esi_data(character_id, kill_id, kill_data, esi_data)

      {:error, esi_error} ->
        log_esi_fetch_error(kill_id, esi_error)
        %{kill_id: kill_id, reason: :fetch_failed}
    end
  end

  # Process ESI data for a kill
  defp process_esi_data(character_id, kill_id, kill_data, esi_data) do
    AppLogger.processor_info("ESI Data", %{
      kill_id: kill_id,
      data: inspect(esi_data)
    })

    # Merge ZKB and ESI data
    merged_data = Map.merge(kill_data, esi_data)

    AppLogger.processor_info("Merged Data", %{
      kill_id: kill_id,
      data: inspect(merged_data)
    })

    # Add basic analysis of why we might have missed it
    analysis = analyze_kill_miss_reason(merged_data, character_id)
    %{kill_id: kill_id, reason: analysis}
  end

  # Log ESI fetch error
  defp log_esi_fetch_error(kill_id, error) do
    AppLogger.processor_error("Failed to get ESI data", %{
      kill_id: kill_id,
      error: inspect(error)
    })
  end

  # Group kills by reason for analysis
  defp group_kills_by_reason(kills_info) do
    kills_info
    |> Enum.group_by(fn %{reason: reason} -> reason end)
    |> Enum.map(fn {reason, kills} ->
      %{
        reason: reason,
        count: length(kills),
        examples: Enum.map(kills, fn %{kill_id: id} -> id end)
      }
    end)
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
    # Get kills from zKillboard - it already returns recent kills
    case ZKillboardApi.get_character_kills(character_id) do
      {:ok, zkill_kills} ->
        log_zkill_response(character_id, zkill_kills)
        process_kill_comparison(character_id, zkill_kills)

      {:error, reason} ->
        log_zkill_fetch_error(character_id, reason)
        {:error, reason}
    end
  end

  # Log ZKill API response details
  defp log_zkill_response(character_id, zkill_kills) do
    AppLogger.processor_info("Raw ZKillboard response", %{
      character_id: character_id,
      total_kills: length(zkill_kills),
      first_kill: List.first(zkill_kills),
      last_kill: List.last(zkill_kills)
    })
  end

  # Log error from ZKill API
  defp log_zkill_fetch_error(character_id, reason) do
    AppLogger.processor_error("Failed to fetch ZKillboard kills", %{
      character_id: character_id,
      error: inspect(reason)
    })
  end

  # Process the kill comparison between ZKill and our database
  defp process_kill_comparison(character_id, zkill_kills) do
    # Get our database kills for comparison
    our_kills = get_our_kills(character_id)
    log_database_kills(character_id, our_kills)

    # Get time window and filter zkill kills
    {now, yesterday} = get_comparison_time_window()
    log_time_window(now, yesterday)

    # Filter zkill kills to last 24 hours
    filtered_zkill_kills = filter_kills_by_time(zkill_kills, yesterday)

    # Process and return comparison results
    generate_comparison_results(our_kills, filtered_zkill_kills)
  end

  # Log our database kills
  defp log_database_kills(character_id, our_kills) do
    AppLogger.processor_info("Raw database kills", %{
      character_id: character_id,
      total_kills: length(our_kills),
      first_kill: if(length(our_kills) > 0, do: List.first(our_kills), else: nil),
      last_kill: if(length(our_kills) > 0, do: List.last(our_kills), else: nil)
    })
  end

  # Get the time window for comparison
  defp get_comparison_time_window do
    now = DateTime.utc_now()
    yesterday = DateTime.add(now, -24 * 60 * 60, :second)
    {now, yesterday}
  end

  # Log the time window used for comparison
  defp log_time_window(now, yesterday) do
    AppLogger.processor_info("Time window", %{
      now: now,
      yesterday: yesterday,
      now_iso: DateTime.to_iso8601(now),
      yesterday_iso: DateTime.to_iso8601(yesterday)
    })
  end

  # Filter kills by time window
  defp filter_kills_by_time(kills, cutoff_date) do
    kills
    |> Enum.filter(fn kill -> kill_after_date?(kill, cutoff_date) end)
  end

  # Check if a kill is after a given date
  defp kill_after_date?(kill, date) do
    # Log each kill's time before parsing
    AppLogger.processor_debug("Processing kill", %{
      kill_id: kill["killmail_id"],
      raw_time: kill["killmail_time"]
    })

    case DateTime.from_iso8601(kill["killmail_time"]) do
      {:ok, kill_time, _} ->
        comparison = DateTime.compare(kill_time, date)
        comparison in [:gt, :eq]

      error ->
        log_kill_time_parse_error(kill, error)
        false
    end
  end

  # Log error when parsing kill time fails
  defp log_kill_time_parse_error(kill, error) do
    AppLogger.processor_error("Failed to parse kill time", %{
      kill_id: kill["killmail_id"],
      kill_time: kill["killmail_time"],
      error: inspect(error)
    })
  end

  # Generate the final comparison results
  defp generate_comparison_results(our_kills, filtered_zkill_kills) do
    # Convert our kills to a map for easier lookup
    our_kill_map = Map.new(our_kills, fn kill -> {kill.killmail_id, kill} end)

    # Find missing and extra kills
    {missing_kills, extra_kills} = analyze_kill_differences(filtered_zkill_kills, our_kill_map)

    # Calculate statistics
    our_kill_count = map_size(our_kill_map)
    zkill_kill_count = length(filtered_zkill_kills)
    missing_count = length(missing_kills)
    extra_count = length(extra_kills)

    # Calculate percentage match and analysis
    {percentage_match, analysis} =
      calculate_match_stats(our_kill_count, zkill_kill_count, missing_count, extra_count)

    {:ok,
     %{
       our_kills: our_kill_count,
       zkill_kills: zkill_kill_count,
       missing_kills: missing_kills,
       extra_kills: extra_kills,
       comparison: %{
         total_difference: missing_count + extra_count,
         percentage_match: percentage_match,
         analysis: analysis
       }
     }}
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
    # Check if database operations are enabled before proceeding
    if TrackedCharacter.database_enabled?() do
      generate_with_database(cache_type, start_datetime, end_datetime)
    else
      generate_without_database(cache_type)
    end
  end

  # Handle the case when database is enabled
  defp generate_with_database(cache_type, start_datetime, end_datetime) do
    case fetch_tracked_characters() do
      {:ok, characters} ->
        process_characters_for_cache(characters, cache_type, start_datetime, end_datetime)

      {:error, reason} ->
        log_character_fetch_error(reason)
        {:error, reason}
    end
  rescue
    e -> handle_comparison_error(e, cache_type)
  end

  # Fetch the tracked characters from the database
  defp fetch_tracked_characters do
    # Check if database is enabled and fetch characters
    if TrackedCharacter.database_enabled?() do
      TrackedCharacter.list_all()
    else
      []
    end
  end

  # Log error when fetching characters fails
  defp log_character_fetch_error(reason) do
    AppLogger.processor_error("Error fetching characters for cache generation", %{
      error: inspect(reason)
    })
  end

  # Process the characters to generate cache data
  defp process_characters_for_cache(characters, cache_type, start_datetime, end_datetime) do
    AppLogger.processor_info("Generating comparison data for cache", %{
      type: cache_type,
      character_count: length(characters)
    })

    character_comparisons =
      gather_character_comparisons(
        characters,
        cache_type,
        start_datetime,
        end_datetime
      )

    # Build and cache the result
    build_and_cache_result(character_comparisons, cache_type)
  end

  # Gather comparisons for all characters with controlled concurrency
  defp gather_character_comparisons(characters, cache_type, start_datetime, end_datetime) do
    characters
    |> Task.async_stream(
      fn character ->
        process_single_character(character, cache_type, start_datetime, end_datetime)
      end,
      max_concurrency: 2,
      timeout: 60_000
    )
    |> Enum.filter(fn
      {:ok, result} when not is_nil(result) -> true
      _ -> false
    end)
    |> Enum.map(fn {:ok, result} -> result end)
    |> Enum.sort_by(fn %{character_name: name} -> name end)
  end

  # Process a single character for comparison
  defp process_single_character(character, cache_type, start_datetime, end_datetime) do
    character_id = extract_character_id(character)
    character_name = extract_character_name(character)

    if is_nil(character_id) do
      nil
    else
      # Rate limiting
      Process.sleep(500)
      get_character_data(character_id, character_name, cache_type, start_datetime, end_datetime)
    end
  end

  # Get character data, either from history or fresh comparison
  defp get_character_data(character_id, character_name, cache_type, start_datetime, end_datetime) do
    case needs_fresh_data?(character_id, cache_type) do
      false ->
        use_historical_data(character_id, character_name, cache_type)

      true ->
        generate_fresh_comparison(
          character_id,
          character_name,
          start_datetime,
          end_datetime,
          cache_type
        )
    end
  end

  # Check if we need fresh data or can use historical
  defp needs_fresh_data?(character_id, cache_type) do
    KillTrackingHistory.needs_refresh?(character_id, cache_type)
  end

  # Use historical data when available
  defp use_historical_data(character_id, character_name, cache_type) do
    case KillTrackingHistory.get_latest_comparison(
           character_id,
           cache_type
         ) do
      {:ok, historical_data} ->
        AppLogger.processor_info("Using historical data for character", %{
          character_id: character_id,
          cache_type: cache_type
        })

        format_character_comparison(character_id, character_name, historical_data)

      _ ->
        # If historical data retrieval fails, return nil and it will be filtered out
        nil
    end
  end

  # Build and cache the final result
  defp build_and_cache_result(character_comparisons, cache_type) do
    # Build the aggregate comparison data
    kill_totals = calculate_kill_totals(character_comparisons)
    comparison_aggregate = calculate_comparison_aggregate(character_comparisons)

    # Create the cache result
    result = %{
      time_range: cache_type,
      character_breakdown: character_comparisons,
      kill_totals: kill_totals,
      comparison_aggregate: comparison_aggregate,
      generated_at: DateTime.utc_now()
    }

    # Cache the result
    CacheRepo.set(
      "kill_comparison:#{cache_type}",
      result,
      86_400 * 7
    )

    # Also save to history if enabled
    save_to_history(character_comparisons, cache_type)

    {:ok, result}
  end

  # Save data to history if database is enabled
  defp save_to_history(character_comparisons, cache_type) do
    if TrackedCharacter.database_enabled?() do
      Enum.each(character_comparisons, fn comp ->
        # Create comparison data map from the comp structure
        comparison_data = %{
          our_kills: comp.our_kills,
          zkill_kills: comp.zkill_kills,
          missing_kills: comp.missing_kills
        }

        KillTrackingHistory.record_comparison(
          comp.character_id,
          comparison_data,
          cache_type
        )
      end)
    end
  end

  # Handle error during comparison generation
  defp handle_comparison_error(e, cache_type) do
    AppLogger.processor_error("Error generating comparison data", %{
      error: Exception.message(e),
      cache_type: cache_type,
      stacktrace: inspect(Exception.format_stacktrace())
    })

    {:error, {:comparison_error, Exception.message(e)}}
  end

  # Generate an empty result when database is disabled
  defp generate_without_database(cache_type) do
    AppLogger.processor_info(
      "Database operations disabled, skipping comparison data generation for #{cache_type}"
    )

    # Create an empty result to return
    empty_result = %{
      time_range: cache_type,
      character_breakdown: [],
      kill_totals: %{our_kills: 0, zkill_kills: 0, missing_kills: 0, extra_kills: 0},
      comparison_aggregate: %{percentage_match: 100, analysis: "Database operations disabled"},
      generated_at: DateTime.utc_now()
    }

    # Cache the empty result to prevent repeated generation attempts
    CacheRepo.set(
      "kill_comparison:#{cache_type}",
      empty_result,
      86_400 * 7
    )

    {:ok, empty_result}
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
    case ZKillboardApi.get_character_kills(character_id) do
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
    cache_key = "esi:killmail:#{kill["killmail_id"]}"

    case CacheRepo.get(cache_key) do
      nil -> fetch_and_check_kill(kill, cache_key, start_date, end_date)
      esi_data -> check_cached_kill(kill, esi_data, start_date, end_date)
    end
  end

  # Fetch a kill from ESI and check if it's in the date range
  defp fetch_and_check_kill(kill, cache_key, start_date, end_date) do
    # Not in cache, fetch from ESI
    case ESIService.get_killmail(
           kill["killmail_id"],
           get_in(kill, ["zkb", "hash"])
         ) do
      {:ok, esi_data} ->
        # Cache the ESI data for 24 hours
        CacheRepo.set(cache_key, esi_data, 86_400)
        check_kill_in_date_range(kill, esi_data, start_date, end_date)

      {:error, reason} ->
        AppLogger.processor_error("Failed to get ESI data", %{
          kill_id: kill["killmail_id"],
          error: inspect(reason)
        })

        :skip
    end
  end

  # Check if a kill from cache is in the date range
  defp check_cached_kill(kill, esi_data, start_date, end_date) do
    check_kill_in_date_range(kill, esi_data, start_date, end_date)
  end

  # Check if a kill is in the requested date range
  defp check_kill_in_date_range(kill, esi_data, start_date, end_date) do
    case DateTime.from_iso8601(esi_data["killmail_time"]) do
      {:ok, kill_date, _} ->
        if DateTime.compare(kill_date, start_date) in [:gt, :eq] and
             DateTime.compare(kill_date, end_date) in [:lt, :eq] do
          {:ok, Map.merge(kill, esi_data)}
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
    AppLogger.processor_info("Full kill data for analysis", %{
      character_id: character_id,
      kill_id: kill_data["killmail_id"],
      kill_time: kill_data["killmail_time"],
      victim_data: %{
        character_id: get_in(kill_data, ["victim", "character_id"]),
        ship_type_id: get_in(kill_data, ["victim", "ship_type_id"]),
        category_id: get_in(kill_data, ["victim", "category_id"])
      },
      attackers:
        Enum.map(kill_data["attackers"] || [], fn attacker ->
          %{
            character_id: attacker["character_id"],
            ship_type_id: attacker["ship_type_id"]
          }
        end),
      zkb_data: get_in(kill_data, ["zkb"])
    })

    # Check each condition in sequence and return the first matching reason
    cond do
      # First check if the character is found in the kill - if found, it's valid
      !not_in_attackers_or_victim?(kill_data, character_id) ->
        AppLogger.processor_info("Kill classified as valid - character found", %{
          kill_id: kill_data["killmail_id"],
          character_id: character_id
        })

        :valid_kill

      # Check if the kill is too old (might have been before tracking started)
      old_kill?(kill_data) ->
        AppLogger.processor_info("Kill classified as too old", %{
          kill_id: kill_data["killmail_id"],
          kill_time: kill_data["killmail_time"]
        })

        :kill_too_old

      # Check if it's an NPC kill
      get_in(kill_data, ["zkb", "npc"]) == true ->
        AppLogger.processor_info("Kill classified as NPC kill", %{
          kill_id: kill_data["killmail_id"],
          zkb_data: get_in(kill_data, ["zkb"])
        })

        :npc_kill

      # Check if it's a structure kill
      structure_kill?(kill_data) ->
        AppLogger.processor_info("Kill classified as structure kill", %{
          kill_id: kill_data["killmail_id"],
          victim_category: get_in(kill_data, ["victim", "category_id"])
        })

        :structure_kill

      # Check if it's a pod kill
      pod_kill?(kill_data) ->
        AppLogger.processor_info("Kill classified as pod kill", %{
          kill_id: kill_data["killmail_id"],
          victim_ship_type: get_in(kill_data, ["victim", "ship_type_id"])
        })

        :pod_kill

      # Default case
      true ->
        AppLogger.processor_info("Kill classified as unknown reason", %{
          kill_id: kill_data["killmail_id"]
        })

        :unknown_reason
    end
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
    victim = kill_data["victim"] || %{}
    # Structure categories in EVE
    # 65 is the structure category
    structure_categories = [65]
    victim["category_id"] in structure_categories
  end

  defp pod_kill?(kill_data) do
    victim = kill_data["victim"] || %{}
    # 670 is the Capsule (pod) type ID
    victim["ship_type_id"] == 670
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
        KillTrackingHistory.record_comparison(
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
end
