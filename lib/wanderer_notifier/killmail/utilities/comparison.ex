defmodule WandererNotifier.Killmail.Utilities.Comparison do
  @moduledoc """
  Compares killmail data between our database and zKillboard.
  Helps identify discrepancies in kill tracking.
  """

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
    case fetch_kill_from_zkill(kill_id) do
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
    hash = extract_hash(kill_data)

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
    case ZKillClient.get_character_kills(character_id) do
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
    KillHistoryService.needs_refresh?(character_id, cache_type)
  end

  # Use historical data when available
  defp use_historical_data(character_id, character_name, cache_type) do
    case KillHistoryService.get_latest_comparison(
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

        KillHistoryService.record_comparison(
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

  # Add these implementations or dummy implementations if needed
  # For brevity, I'm including placeholders - you'll need to fill these in

  # Extract hash from kill data
  defp extract_hash(kill_data) do
    get_in(kill_data, ["zkb", "hash"])
  end

  # Analyze why a kill was missed
  defp analyze_kill_miss_reason(kill_data, character_id) do
    # Check if character was involved
    if character_involved?(kill_data, character_id) do
      # Determine if it's a specific type we might filter out
      cond do
        is_pod_kill?(kill_data) -> :pod_kill
        is_structure_kill?(kill_data) -> :structure_kill
        is_npc_kill?(kill_data) -> :npc_kill
        true -> :unknown
      end
    else
      :character_not_involved
    end
  end

  # Check if character was involved in kill
  defp character_involved?(kill_data, character_id) do
    character_id_str = to_string(character_id)

    # Check if character is victim
    victim_id = get_in(kill_data, ["victim", "character_id"])
    victim_match = victim_id && to_string(victim_id) == character_id_str

    if victim_match do
      true
    else
      # Check attackers
      attackers = get_in(kill_data, ["attackers"]) || []

      Enum.any?(attackers, fn attacker ->
        attacker_id = Map.get(attacker, "character_id")
        attacker_id && to_string(attacker_id) == character_id_str
      end)
    end
  end

  # Check if it's a pod kill
  defp is_pod_kill?(kill_data) do
    victim_ship_type_id = get_in(kill_data, ["victim", "ship_type_id"])
    victim_ship_type_id == @pod_type_id
  end

  # Check if it's a structure kill
  defp is_structure_kill?(kill_data) do
    victim_category_id = get_in(kill_data, ["victim", "category_id"])
    victim_category_id == @structure_category_id
  end

  # Check if it's an NPC kill
  defp is_npc_kill?(kill_data) do
    is_npc = get_in(kill_data, ["zkb", "npc"])
    is_npc == true
  end

  # Get our kills for a character from the database
  defp get_our_kills(character_id) do
    # This function will depend on your database implementation
    # Return a list of killmail objects
    query =
      Killmail
      |> filter(related_character_id == ^character_id)

    case Api.read(query) do
      {:ok, kills} -> kills
      _ -> []
    end
  end

  # Analyze differences between our kills and zkill
  defp analyze_kill_differences(zkill_kills, our_kill_map) do
    # Find kills that exist in zkill but not in our database
    missing_kills =
      zkill_kills
      |> Enum.filter(fn kill ->
        zkill_id = kill["killmail_id"]
        !Map.has_key?(our_kill_map, zkill_id)
      end)
      |> Enum.map(fn kill -> kill["killmail_id"] end)

    # Find kills that exist in our database but not in zkill
    zkill_ids = MapSet.new(zkill_kills, & &1["killmail_id"])

    extra_kills =
      our_kill_map
      |> Map.keys()
      |> Enum.filter(fn our_id -> !MapSet.member?(zkill_ids, our_id) end)

    {missing_kills, extra_kills}
  end

  # Calculate match statistics
  defp calculate_match_stats(our_count, zkill_count, missing_count, extra_count) do
    # Calculate a percentage match based on how many kills match between systems
    percent_match =
      if zkill_count == 0 do
        100.0
      else
        matched_count = zkill_count - missing_count
        (matched_count / zkill_count) * 100
      end

    # Round to one decimal place
    rounded_percent = Float.round(percent_match, 1)

    # Generate an analysis message
    analysis =
      cond do
        missing_count == 0 and extra_count == 0 ->
          "Perfect match: All kills are correctly tracked."

        missing_count > 0 and extra_count == 0 ->
          "Missing kills: We're missing #{missing_count} kill(s) from zKillboard."

        missing_count == 0 and extra_count > 0 ->
          "Extra kills: We have #{extra_count} kill(s) that aren't on zKillboard."

        true ->
          "Mixed issues: Missing #{missing_count} and have #{extra_count} extra kill(s)."
      end

    {rounded_percent, analysis}
  end

  # Calculate comparison stats
  defp calculate_comparison_stats(our_kill_ids, zkill_kill_ids, missing_kills, extra_kills) do
    # Calculate percentage match (what percent of zkill kills do we have?)
    percent_match =
      if MapSet.size(zkill_kill_ids) == 0 do
        100.0
      else
        matched_count = MapSet.size(zkill_kill_ids) - MapSet.size(missing_kills)
        (matched_count / MapSet.size(zkill_kill_ids)) * 100
      end

    # Round to one decimal place
    rounded_percent = Float.round(percent_match, 1)

    # Generate an analysis message
    analysis =
      cond do
        MapSet.size(missing_kills) == 0 and MapSet.size(extra_kills) == 0 ->
          "Perfect match: All kills are correctly tracked."

        MapSet.size(missing_kills) > 0 and MapSet.size(extra_kills) == 0 ->
          "Missing kills: We're missing #{MapSet.size(missing_kills)} kill(s) from zKillboard."

        MapSet.size(missing_kills) == 0 and MapSet.size(extra_kills) > 0 ->
          "Extra kills: We have #{MapSet.size(extra_kills)} kill(s) that aren't on zKillboard."

        true ->
          "Mixed issues: Missing #{MapSet.size(missing_kills)} and have #{MapSet.size(extra_kills)} extra kill(s)."
      end

    %{
      total_difference: MapSet.size(missing_kills) + MapSet.size(extra_kills),
      percentage_match: rounded_percent,
      analysis: analysis
    }
  end

  # Extract character ID from a character object
  defp extract_character_id(character) do
    cond do
      is_map(character) && Map.has_key?(character, :character_id) ->
        character.character_id
      is_map(character) && Map.has_key?(character, "character_id") ->
        character["character_id"]
      true -> nil
    end
  end

  # Extract character name from a character object
  defp extract_character_name(character) do
    cond do
      is_map(character) && Map.has_key?(character, :character_name) ->
        character.character_name
      is_map(character) && Map.has_key?(character, "character_name") ->
        character["character_name"]
      true -> "Unknown"
    end
  end

  # Generate a fresh comparison for a character
  defp generate_fresh_comparison(character_id, character_name, start_datetime, end_datetime, cache_type) do
    # Perform a fresh comparison between our database and zKillboard
    case compare_killmails(character_id, start_datetime, end_datetime) do
      {:ok, comparison_data} ->
        # Format the character comparison for cache
        format_character_comparison(character_id, character_name, comparison_data)

      {:error, reason} ->
        AppLogger.processor_error("Error generating fresh comparison", %{
          character_id: character_id,
          character_name: character_name,
          error: inspect(reason)
        })

        nil
    end
  end

  # Format character comparison data for caching
  defp format_character_comparison(character_id, character_name, comparison_data) do
    %{
      character_id: character_id,
      character_name: character_name,
      our_kills: comparison_data.our_kills || 0,
      zkill_kills: comparison_data.zkill_kills || 0,
      missing_kills: comparison_data.missing_kills || [],
      extra_kills: comparison_data.extra_kills || [],
      percentage_match: (comparison_data.comparison || %{}).percentage_match || 0
    }
  end

  # Calculate total kills across all characters
  defp calculate_kill_totals(character_comparisons) do
    initial_totals = %{
      our_kills: 0,
      zkill_kills: 0,
      missing_kills: 0,
      extra_kills: 0
    }

    Enum.reduce(character_comparisons, initial_totals, fn comp, totals ->
      %{
        our_kills: totals.our_kills + comp.our_kills,
        zkill_kills: totals.zkill_kills + comp.zkill_kills,
        missing_kills: totals.missing_kills + length(comp.missing_kills),
        extra_kills: totals.extra_kills + length(comp.extra_kills)
      }
    end)
  end

  # Calculate aggregate comparison statistics
  defp calculate_comparison_aggregate(character_comparisons) do
    # Calculate average percentage match across all characters
    total_percentage = Enum.reduce(character_comparisons, 0, fn comp, acc ->
      acc + comp.percentage_match
    end)

    avg_percentage =
      if length(character_comparisons) > 0 do
        total_percentage / length(character_comparisons)
      else
        100.0
      end

    # Round to one decimal place
    rounded_percent = Float.round(avg_percentage, 1)

    # Generate an overall analysis
    total_missing = Enum.reduce(character_comparisons, 0, fn comp, acc ->
      acc + length(comp.missing_kills)
    end)

    total_extra = Enum.reduce(character_comparisons, 0, fn comp, acc ->
      acc + length(comp.extra_kills)
    end)

    analysis =
      cond do
        total_missing == 0 and total_extra == 0 ->
          "Perfect tracking: All kills match across all characters."

        rounded_percent >= 95 ->
          "Excellent tracking: #{rounded_percent}% of kills are correctly tracked."

        rounded_percent >= 80 ->
          "Good tracking: #{rounded_percent}% of kills are tracked, but missing #{total_missing} kills."

        rounded_percent >= 60 ->
          "Fair tracking: #{rounded_percent}% of kills tracked, missing #{total_missing} kills."

        true ->
          "Poor tracking: Only #{rounded_percent}% of kills are tracked. Missing #{total_missing} kills."
      end

    %{
      percentage_match: rounded_percent,
      analysis: analysis
    }
  end

  # Fetch kills from zKillboard
  defp fetch_zkill_kills(character_id, start_date, end_date) do
    case ZKillClient.get_character_kills(character_id) do
      {:ok, kills} ->
        # Filter kills by date
        filtered_kills =
          kills
          |> Enum.filter(fn kill ->
            case DateTime.from_iso8601(kill["killmail_time"]) do
              {:ok, kill_time, _} ->
                DateTime.compare(kill_time, start_date) in [:gt, :eq] and
                  DateTime.compare(kill_time, end_date) in [:lt, :eq]
              _ -> false
            end
          end)

        {:ok, filtered_kills}

      error -> error
    end
  end

  # Fetch a kill from zKillboard
  defp fetch_kill_from_zkill(kill_id) do
    ZKillClient.get_killmail(kill_id)
  end

  # Fetch our kills from the database
  defp fetch_our_kills(character_id, start_date, end_date) do
    query =
      Killmail
      |> filter(related_character_id == ^character_id)
      |> filter(kill_time >= ^start_date)
      |> filter(kill_time <= ^end_date)

    case Api.read(query) do
      {:ok, kills} -> {:ok, kills}
      error -> error
    end
  end
end
