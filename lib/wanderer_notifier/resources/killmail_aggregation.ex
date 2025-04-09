defmodule WandererNotifier.Resources.KillmailAggregation do
  @moduledoc """
  Handles aggregating killmail data for statistical analysis.
  Provides functions for analyzing and grouping killmail data by character.
  """

  use Ash.Resource,
    domain: WandererNotifier.Resources.Api,
    extensions: []

  alias WandererNotifier.Config.Timings
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

  # Filter kills for a specific time period
  defp filter_period(killmails, start_date, end_date) do
    Enum.filter(killmails, fn kill ->
      kill_time = kill.kill_time

      # Check if the kill is in the date range
      DateTime.compare(kill_time, start_date) != :lt &&
        DateTime.compare(kill_time, end_date) != :gt
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
      final_blows: stats.final_blow_count,
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
      final_blow_count: stats.final_blow_count,
      region_activity: stats.region_activity,
      ship_usage: stats.ship_usage,
      top_victim_corps: stats.top_victim_corps,
      top_victim_ships: stats.top_victim_ships,
      detailed_ship_usage: stats.detailed_ship_usage,
      kill_death_ratio: stats.kill_death_ratio,
      efficiency: stats.efficiency
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

  # Calculate aggregate statistics from a list of killmails
  defp calculate_statistics(killmails) do
    # Split by role (attacker vs victim)
    {kills, deaths} = split_kills_by_role(killmails)

    # Calculate value stats - using total_value from normalized model
    kills_isk_destroyed = sum_killmail_values(kills)
    deaths_isk_lost = sum_killmail_values(deaths)

    # Count solo kills (using is_solo flag from normalized model)
    solo_kills_count = Enum.count(kills, & &1.is_solo)

    # Count final blows (more complex with normalized model - need to check character involvement)
    final_blow_count = count_final_blows(kills)

    # Prepare statistics structure
    %{
      kills_count: length(kills),
      deaths_count: length(deaths),
      isk_destroyed: kills_isk_destroyed,
      isk_lost: deaths_isk_lost,
      solo_kills_count: solo_kills_count,
      final_blow_count: final_blow_count,
      kill_death_ratio: calculate_kd_ratio(length(kills), length(deaths)),
      efficiency: calculate_efficiency(length(kills), length(deaths))
    }
  end

  # Split killmails by role (attacker vs victim)
  defp split_kills_by_role(killmails) do
    # With the normalized model, we need to check the character involvement
    # This needs to be updated to work with either direct killmails or
    # killmails with associated character involvements loaded
    Enum.reduce(killmails, {[], []}, fn killmail, {kills, deaths} ->
      case get_killmail_role(killmail) do
        :attacker -> {[killmail | kills], deaths}
        :victim -> {kills, [killmail | deaths]}
        # Skip if role can't be determined
        _ -> {kills, deaths}
      end
    end)
  end

  # Determine the role for a killmail
  # Handle both loaded character involvements or direct killmail records
  defp get_killmail_role(killmail) do
    cond do
      # If character_role is directly available
      Map.has_key?(killmail, :character_role) ->
        killmail.character_role

      # If character involvement is loaded
      Map.has_key?(killmail, :character_involvements) &&
          not Enum.empty?(killmail.character_involvements) ->
        hd(killmail.character_involvements).character_role

      # Use legacy method if none of the above
      Map.has_key?(killmail, :related_character_id) &&
          not is_nil(killmail.related_character_id) ->
        parse_related_character_role(killmail)

      true ->
        # Unable to determine role
        nil
    end
  end

  # Parse role from legacy killmail format
  defp parse_related_character_role(killmail) do
    if is_map(killmail.victim_data) &&
         to_string(Map.get(killmail.victim_data, "character_id", "")) ==
           to_string(killmail.related_character_id) do
      :victim
    else
      :attacker
    end
  end

  # Convert a value to Decimal
  defp to_decimal(value) when is_struct(value, Decimal), do: value
  defp to_decimal(value) when is_integer(value), do: Decimal.new(value)
  defp to_decimal(value) when is_float(value), do: value |> Float.to_string() |> Decimal.new()

  defp to_decimal(value) when is_binary(value) do
    case Decimal.parse(value) do
      {decimal, ""} -> decimal
      _ -> Decimal.new(0)
    end
  end

  defp to_decimal(_), do: Decimal.new(0)

  # Sum the total values for a list of killmails
  defp sum_killmail_values(values) do
    values
    |> Enum.map(&to_decimal/1)
    |> Enum.reduce(Decimal.new(0), &Decimal.add/2)
  end

  # Count final blows in kills
  defp count_final_blows(kills) do
    Enum.count(kills, fn kill ->
      # Check if we have character involvements loaded
      if Map.has_key?(kill, :character_involvements) &&
           not Enum.empty?(kill.character_involvements) do
        # Check if the character's involvement has final_blow = true
        Enum.any?(kill.character_involvements, & &1.is_final_blow)
      else
        # Legacy check - less accurate
        kill.final_blow_attacker_id == kill.related_character_id
      end
    end)
  end

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
    Timings.persistence_config()
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

  # Calculate kill/death ratio
  defp calculate_kd_ratio(kills, deaths) do
    case deaths do
      0 -> kills
      _ -> kills / deaths
    end
  end

  # Calculate efficiency percentage
  defp calculate_efficiency(kills, deaths) do
    total = kills + deaths

    case total do
      0 -> 0.0
      _ -> kills / total * 100.0
    end
  end
end
