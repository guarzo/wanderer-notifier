defmodule WandererNotifier.Resources.KillmailAggregation do
  @moduledoc """
  Handles aggregating killmail data for statistical analysis.
  Provides functions for analyzing and grouping killmail data by character.
  """

  use Ash.Resource,
    domain: WandererNotifier.Resources.Domain,
    extensions: []

  alias Timings
  alias WandererNotifier.Logger.Logger, as: AppLogger
  alias WandererNotifier.Resources.Api
  alias WandererNotifier.Resources.Killmail
  alias WandererNotifier.Resources.KillmailStatistic
  alias WandererNotifier.Resources.TrackedCharacter

  require Ash.Query, as: Query

  def get_recent_killmails(limit \\ 100) do
    AppLogger.persistence_info("Fetching recent killmails", %{limit: limit})

    case Killmail
         |> Query.sort(kill_time: :desc)
         |> Query.limit(limit)
         |> Api.read() do
      {:ok, killmails} ->
        AppLogger.persistence_info("Retrieved recent killmails", %{
          count: length(killmails)
        })

        killmails

      {:error, error} ->
        AppLogger.persistence_error("Failed to retrieve recent killmails", %{
          error: inspect(error)
        })

        []
    end
  rescue
    e ->
      AppLogger.persistence_error("Exception retrieving recent killmails", %{
        error: Exception.message(e)
      })

      # Log stacktrace properly
      stacktrace = __STACKTRACE__

      AppLogger.persistence_debug("Exception stacktrace", %{
        stacktrace: Exception.format_stacktrace(stacktrace)
      })

      []
  end

  @doc """
  Aggregates killmail data for all tracked characters.
  Calculates statistics and updates database records.
  """
  def aggregate_all_character_killmails do
    AppLogger.persistence_info("Starting killmail aggregation for all characters")

    # Get all tracked characters
    case TrackedCharacter.list_all() do
      {:ok, characters} ->
        if characters == [] do
          AppLogger.persistence_warn("No characters to process")
          {:ok, %{characters: %{}, processed: 0}}
        else
          process_characters(characters)
        end

      {:error, error} ->
        AppLogger.persistence_error("Error fetching characters: #{inspect(error)}")
        {:error, "Failed to fetch characters"}
    end
  end

  # Process a list of characters
  defp process_characters(characters) do
    AppLogger.persistence_info("Processing tracked characters", %{
      count: length(characters)
    })

    # Process each character and collect results
    results =
      characters
      |> Enum.map(fn character ->
        {character, aggregate_character_killmails(character)}
      end)

    # Count successful and failed operations
    character_results =
      Enum.reduce(results, %{}, fn {character, result}, acc ->
        status = if result == :ok, do: :success, else: :error
        Map.put(acc, character.character_id, %{name: character.character_name, status: status})
      end)

    processed_count = Enum.count(results, fn {_, result} -> result == :ok end)

    AppLogger.persistence_info("Character aggregation complete", %{
      total: length(characters),
      processed: processed_count
    })

    {:ok, %{characters: character_results, processed: processed_count}}
  end

  # Delete older killmails to maintain database size
  def clean_old_killmails(days_to_keep \\ nil) do
    days = days_to_keep || get_retention_period()
    cutoff_date = DateTime.add(DateTime.utc_now(), -days * 86_400, :second)

    AppLogger.persistence_info("Cleaning killmails older than cutoff date", %{
      days_to_keep: days,
      cutoff_date: cutoff_date
    })

    # Find old killmails
    query =
      Killmail
      |> Query.filter(kill_time < ^cutoff_date)
      |> Query.limit(1000)

    with {:ok, old_killmails} <- Api.read(query),
         count = length(old_killmails),
         true <- count > 0 do
      AppLogger.persistence_info("Found killmails to delete", %{count: count})

      # Delete in batches
      {success, errors} = delete_in_batches(old_killmails)

      AppLogger.persistence_info("Killmail cleanup complete", %{
        deleted: success,
        errors: errors
      })

      {:ok, %{deleted: success, errors: errors}}
    else
      {:error, error} ->
        AppLogger.persistence_error("Error finding old killmails", %{
          error: inspect(error)
        })

        {:error, error}

      _ ->
        AppLogger.persistence_debug("No old killmails to clean up")
        {:ok, %{deleted: 0, errors: 0}}
    end
  rescue
    e ->
      AppLogger.persistence_error("Exception during killmail cleanup", %{
        error: Exception.message(e)
      })

      # Log stacktrace properly
      stacktrace = __STACKTRACE__

      AppLogger.persistence_debug("Exception stacktrace", %{
        stacktrace: Exception.format_stacktrace(stacktrace)
      })

      {:error, e}
  end

  @doc """
  Aggregates killmail data for a specific period (daily, weekly, monthly).
  This function is called by the KillmailAggregationScheduler.

  Returns:
  - {:ok, stats} where stats contains information about the aggregation
  - {:error, reason} on failure
  """
  def aggregate_for_period(period_type, date) do
    AppLogger.persistence_info("Starting #{period_type} aggregation for date", %{
      date: Date.to_string(date)
    })

    try do
      # Get all tracked characters
      case TrackedCharacter.list_all() do
        {:ok, characters} ->
          if characters == [] do
            AppLogger.persistence_warn("No characters for period aggregation")
            {:ok, %{characters: %{}, processed: 0}}
          else
            process_period_characters(characters, period_type, date)
          end

        {:error, error} ->
          AppLogger.persistence_error("Error fetching characters for period aggregation", %{
            error: inspect(error)
          })

          {:error, "Failed to fetch characters"}
      end
    rescue
      e ->
        stacktrace = __STACKTRACE__

        AppLogger.persistence_error("Exception during period aggregation", %{
          period_type: period_type,
          date: Date.to_string(date),
          error: Exception.message(e)
        })

        AppLogger.persistence_debug("Exception stacktrace", %{
          stacktrace: Exception.format_stacktrace(stacktrace)
        })

        {:error, "Exception: #{Exception.message(e)}"}
    end
  end

  # Process all characters for a specific period
  defp process_period_characters(characters, period_type, date) do
    AppLogger.persistence_info("Processing period aggregation for characters", %{
      period_type: period_type,
      date: Date.to_string(date),
      count: length(characters)
    })

    # Calculate period start and end dates
    period_dates = calculate_period_dates(period_type, date)

    # Process each character and aggregate stats
    results =
      characters
      |> Enum.map(fn character ->
        period_result =
          process_character_period(
            character,
            period_type,
            period_dates.start_date,
            period_dates.end_date
          )

        {character, period_result}
      end)

    # Count successes and failures
    character_results =
      Enum.reduce(results, %{}, fn {character, result}, acc ->
        status = if elem(result, 0) == :ok, do: :success, else: :error

        Map.put(acc, character.character_id, %{
          name: character.character_name,
          status: status
        })
      end)

    success_count = Enum.count(results, fn {_, result} -> elem(result, 0) == :ok end)

    AppLogger.persistence_info("Period aggregation complete", %{
      period_type: period_type,
      total: length(characters),
      success: success_count
    })

    {:ok, %{characters: character_results, processed: success_count}}
  end

  # Calculate period start and end dates
  defp calculate_period_dates(period_type, _reference_date) do
    now = DateTime.utc_now()

    case period_type do
      :daily ->
        # 24 hour period ending now
        start_date = DateTime.add(now, -86_400, :second)
        %{start_date: start_date, end_date: now}

      :weekly ->
        # Calculate week start (Monday)
        today = DateTime.to_date(now)
        days_since_monday = Date.day_of_week(today) - 1

        # Get datetime for start of current week (Monday)
        monday = Date.add(today, -days_since_monday)
        start_of_monday = DateTime.new!(monday, ~T[00:00:00])

        %{start_date: start_of_monday, end_date: now}

      :monthly ->
        # 30 day period ending now
        start_date = DateTime.add(now, -30 * 86_400, :second)
        %{start_date: start_date, end_date: now}

      _ ->
        # Default to daily if unknown
        start_date = DateTime.add(now, -86_400, :second)
        %{start_date: start_date, end_date: now}
    end
  end

  # Process a single character for the period
  defp process_character_period(character, period_type, start_date, end_date) do
    AppLogger.persistence_info("Processing character for period", %{
      character_name: character.character_name,
      period_type: period_type
    })

    # Get killmails for this character
    killmails = get_character_killmails(character)

    # Filter for the period
    period_killmails = filter_period(killmails, start_date, end_date)

    # Calculate stats
    stats = calculate_statistics(period_killmails)

    # Log statistics summary
    log_character_statistics(character, stats)

    # Save to database
    case save_character_statistics(
           character,
           stats,
           Atom.to_string(period_type),
           start_date,
           end_date,
           character.character_id
         ) do
      :ok -> {:ok, stats}
      error -> error
    end
  end

  # Aggregate killmails for a single character
  def aggregate_character_killmails(character) do
    AppLogger.persistence_info("Aggregating killmails for character", %{
      character_id: character.character_id,
      character_name: character.character_name
    })

    # Get all killmails for this character
    killmails = get_character_killmails(character)

    # Calculate statistics for different time periods
    process_character_periods(character, killmails)
  rescue
    e ->
      AppLogger.persistence_error("Exception during character killmail aggregation", %{
        character_id: character.character_id,
        character_name: character.character_name,
        error: Exception.message(e)
      })

      stacktrace = __STACKTRACE__

      AppLogger.persistence_debug("Error stacktrace", %{
        stacktrace: Exception.format_stacktrace(stacktrace)
      })

      {:error, e}
  end

  # Process different time periods for a character
  defp process_character_periods(character, killmails) do
    now = DateTime.utc_now()

    # Last 24 hours_
    one_day_ago = DateTime.add(now, -86_400, :second)
    last_24h_kills = filter_period(killmails, one_day_ago, now)
    last_24h_stats = calculate_statistics(last_24h_kills)

    AppLogger.persistence_info("Daily statistics calculated", %{
      character_name: character.character_name,
      kills: last_24h_stats.kills_count,
      deaths: last_24h_stats.deaths_count
    })

    # Save statistics for this period
    save_character_statistics(
      character,
      last_24h_stats,
      "daily",
      one_day_ago,
      now,
      character.character_id
    )

    # Last 7 days
    seven_days_ago = DateTime.add(now, -7 * 86_400, :second)
    last_7d_kills = filter_period(killmails, seven_days_ago, now)
    last_7d_stats = calculate_statistics(last_7d_kills)

    AppLogger.persistence_info("Weekly statistics calculated", %{
      character_name: character.character_name,
      kills: last_7d_stats.kills_count,
      deaths: last_7d_stats.deaths_count
    })

    # Save statistics for this period
    save_character_statistics(
      character,
      last_7d_stats,
      "weekly",
      seven_days_ago,
      now,
      character.character_id
    )

    # Last 30 days
    thirty_days_ago = DateTime.add(now, -30 * 86_400, :second)
    last_30d_kills = filter_period(killmails, thirty_days_ago, now)
    last_30d_stats = calculate_statistics(last_30d_kills)

    AppLogger.persistence_info("Monthly statistics calculated", %{
      character_name: character.character_name,
      kills: last_30d_stats.kills_count,
      deaths: last_30d_stats.deaths_count
    })

    # Save statistics for this period
    save_character_statistics(
      character,
      last_30d_stats,
      "monthly",
      thirty_days_ago,
      now,
      character.character_id
    )

    :ok
  end

  # Filter killmails for a specific time period
  defp filter_period(killmails, start_time, end_time) do
    Enum.filter(killmails, fn killmail ->
      DateTime.compare(killmail.kill_time, start_time) != :lt &&
        DateTime.compare(killmail.kill_time, end_time) != :gt
    end)
  end

  # Get all killmails for a character
  defp get_character_killmails(character) do
    case Killmail
         |> Query.filter(related_character_id == ^character.character_id)
         |> Api.read() do
      {:ok, killmails} ->
        AppLogger.persistence_info("Retrieved character killmails", %{
          character_name: character.character_name,
          count: length(killmails)
        })

        killmails

      error ->
        AppLogger.persistence_error("Error querying killmails", %{
          character_name: character.character_name,
          error: inspect(error)
        })

        []
    end
  end

  # Log statistics summary for a character
  defp log_character_statistics(character, stats) do
    AppLogger.persistence_info("Character statistics summary", %{
      character_name: character.character_name,
      kills: stats.kills_count,
      deaths: stats.deaths_count,
      solo_kills: stats.solo_kills_count,
      final_blows: stats.final_blows_count,
      isk_destroyed: Decimal.to_string(stats.isk_destroyed),
      regions: map_size(stats.region_activity),
      ships: map_size(stats.ship_usage)
    })
  end

  # Create statistics attributes map
  defp build_statistics_attributes(
         stats,
         period_type,
         period_start,
         period_end,
         character_id,
         character_name
       ) do
    %{
      period_type: period_type,
      period_start: period_start,
      period_end: period_end,
      character_id: character_id,
      character_name: character_name,
      kills_count: stats.kills_count,
      deaths_count: stats.deaths_count,
      isk_destroyed: stats.isk_destroyed,
      isk_lost: stats.isk_lost,
      solo_kills_count: stats.solo_kills_count,
      final_blows_count: stats.final_blows_count,
      region_activity: stats.region_activity,
      ship_usage: stats.ship_usage,
      top_victim_corps: stats.top_victim_corps,
      top_victim_ships: stats.top_victim_ships,
      detailed_ship_usage: stats.detailed_ship_usage
    }
  end

  # Update or create a statistics record
  defp save_character_statistics(
         character,
         stats,
         period_type,
         period_start,
         period_end,
         character_id
       ) do
    # Find existing statistic record for this period
    existing_stat =
      find_existing_statistics(character_id, period_type, period_start, character.character_name)

    # Create the statistics attributes map
    statistic_attrs =
      build_statistics_attributes(
        stats,
        period_type,
        period_start,
        period_end,
        character_id,
        character.character_name
      )

    if existing_stat do
      update_existing_statistics(existing_stat, statistic_attrs, character.character_name)
    else
      create_new_statistics(statistic_attrs, character.character_name)
    end
  end

  # Find existing statistics record
  defp find_existing_statistics(character_id, period_type, period_start, character_name) do
    result =
      KillmailStatistic
      |> Query.filter(character_id: character_id)
      |> Query.filter(period_type: period_type)
      |> Query.filter(period_start: period_start)
      |> Api.read()

    case result do
      {:ok, [stat | _]} ->
        stat

      {:ok, []} ->
        nil

      error ->
        AppLogger.persistence_error("Error finding existing statistics", %{
          character_name: character_name,
          error: inspect(error)
        })

        nil
    end
  end

  # Update existing statistics record
  defp update_existing_statistics(existing_stat, statistic_attrs, character_name) do
    AppLogger.persistence_info("Updating existing statistics", %{
      character_name: character_name
    })

    result =
      Api.update(
        KillmailStatistic,
        existing_stat.id,
        statistic_attrs,
        action: :update
      )

    case result do
      {:ok, _updated} ->
        AppLogger.persistence_info("Successfully updated statistics", %{
          character_name: character_name
        })

        :ok

      error ->
        AppLogger.persistence_error("Error updating statistics", %{
          character_name: character_name,
          error: inspect(error)
        })

        {:error, error}
    end
  end

  # Create new statistics record
  defp create_new_statistics(statistic_attrs, character_name) do
    AppLogger.persistence_info("Creating new statistics", %{
      character_name: character_name
    })

    result =
      Api.create(KillmailStatistic, statistic_attrs, action: :create)

    case result do
      {:ok, _created} ->
        AppLogger.persistence_info("Successfully created statistics", %{
          character_name: character_name
        })

        :ok

      error ->
        AppLogger.persistence_error("Error creating statistics", %{
          character_name: character_name,
          error: inspect(error)
        })

        {:error, error}
    end
  end

  # Calculate statistics from killmails
  defp calculate_statistics(killmails) do
    # Initialize empty statistics
    initial_stats = %{
      kills_count: 0,
      deaths_count: 0,
      isk_destroyed: Decimal.new(0),
      isk_lost: Decimal.new(0),
      solo_kills_count: 0,
      final_blows_count: 0,
      region_activity: %{},
      ship_usage: %{},
      top_victim_corps: %{},
      top_victim_ships: %{},
      detailed_ship_usage: %{}
    }

    # Process each killmail and aggregate statistics
    Enum.reduce(killmails, initial_stats, fn killmail, acc ->
      case killmail.character_role do
        :attacker -> process_kill(killmail, acc)
        :victim -> process_death(killmail, acc)
      end
    end)
  end

  # Process a kill (when character is attacker)
  defp process_kill(killmail, stats) do
    # This is a kill
    kills_count = stats.kills_count + 1
    isk_destroyed = Decimal.add(stats.isk_destroyed, killmail.total_value || Decimal.new(0))

    # Solo kill tracking
    solo_kills_count = update_solo_kills_count(stats.solo_kills_count, killmail.zkb_data)

    # Final blow tracking
    final_blows_count = update_final_blows_count(stats.final_blows_count, killmail.attacker_data)

    # Update region and ship stats
    region_activity = update_region_count(stats.region_activity, killmail.region_name)
    ship_usage = update_ship_usage(stats.ship_usage, killmail.ship_type_name)

    # Process victim data
    {top_victim_corps, top_victim_ships, detailed_ship_usage} =
      process_victim_data(
        stats.top_victim_corps,
        stats.top_victim_ships,
        stats.detailed_ship_usage,
        killmail
      )

    # Return updated statistics
    %{
      stats
      | kills_count: kills_count,
        isk_destroyed: isk_destroyed,
        solo_kills_count: solo_kills_count,
        final_blows_count: final_blows_count,
        region_activity: region_activity,
        ship_usage: ship_usage,
        top_victim_corps: top_victim_corps,
        top_victim_ships: top_victim_ships,
        detailed_ship_usage: detailed_ship_usage
    }
  end

  # Process a death (when character is victim)
  defp process_death(killmail, stats) do
    deaths_count = stats.deaths_count + 1
    isk_lost = Decimal.add(stats.isk_lost, killmail.total_value || Decimal.new(0))

    %{stats | deaths_count: deaths_count, isk_lost: isk_lost}
  end

  # Check and update solo kills count
  defp update_solo_kills_count(current_count, zkb_data) do
    zkb_data = zkb_data || %{}
    is_solo = Map.get(zkb_data, "solo", false) == true

    if is_solo, do: current_count + 1, else: current_count
  end

  # Check and update final blows count
  defp update_final_blows_count(current_count, attacker_data) do
    attacker_data = attacker_data || %{}
    is_final_blow = Map.get(attacker_data, "final_blow", false) in [true, "true"]

    if is_final_blow, do: current_count + 1, else: current_count
  end

  # Process victim data and update relevant statistics
  defp process_victim_data(top_victim_corps, top_victim_ships, detailed_ship_usage, killmail) do
    victim_data = killmail.victim_data || %{}

    # Extract victim corporation
    victim_corp = Map.get(victim_data, "corporation_name", "Unknown")
    updated_corps = update_count_map(top_victim_corps, victim_corp)

    # Extract victim ship
    victim_ship = Map.get(victim_data, "ship_type_name", "Unknown")
    updated_ships = update_count_map(top_victim_ships, victim_ship)

    # Update detailed ship usage (which ship was used to kill which ship)
    detailed_usage_key = "#{killmail.ship_type_name || "Unknown"} → #{victim_ship}"
    updated_detail = update_count_map(detailed_ship_usage, detailed_usage_key)

    {updated_corps, updated_ships, updated_detail}
  end

  # Update count in a map for a given key
  defp update_count_map(map, key) when is_binary(key) do
    Map.update(map, key, 1, &(&1 + 1))
  end

  defp update_count_map(map, _), do: map

  # Update region count in a map
  defp update_region_count(region_map, region_name) when is_binary(region_name) do
    Map.update(region_map, region_name, 1, &(&1 + 1))
  end

  defp update_region_count(region_map, _), do: region_map

  # Update ship usage count in a map
  defp update_ship_usage(ship_map, ship_name) when is_binary(ship_name) do
    Map.update(ship_map, ship_name, 1, &(&1 + 1))
  end

  defp update_ship_usage(ship_map, _), do: ship_map

  # Delete records in batches to avoid memory issues
  defp delete_in_batches(records, batch_size \\ 100) do
    records
    |> Enum.chunk_every(batch_size)
    |> Enum.reduce({0, 0}, fn batch, {success_count, error_count} ->
      {batch_success, batch_errors} = delete_batch(batch)
      {success_count + batch_success, error_count + batch_errors}
    end)
  end

  # Delete a batch of records
  defp delete_batch(batch) do
    batch_results =
      Enum.map(batch, fn killmail ->
        # Use proper destroy pattern for Ash resources
        Api.destroy(Killmail, killmail.id)
      end)

    # Count successes and errors
    successes =
      Enum.count(batch_results, fn
        {:ok, _} -> true
        _ -> false
      end)

    errors = length(batch_results) - successes

    {successes, errors}
  end

  # Get the retention period from config
  defp get_retention_period do
    WandererNotifier.Config.Timings.persistence_config()
    |> Keyword.get(:retention_period_days, 180)
  end

  @doc """
  Aggregates killmail statistics for a specific period type and date.
  This is an alias for aggregate_for_period to maintain API compatibility.
  """
  def aggregate_statistics(period_type, date \\ Date.utc_today()) do
    case aggregate_for_period(period_type, date) do
      {:ok, _stats} -> :ok
      error -> error
    end
  end
end
