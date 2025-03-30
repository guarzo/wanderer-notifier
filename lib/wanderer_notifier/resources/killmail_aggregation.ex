defmodule WandererNotifier.Resources.KillmailAggregation do
  @moduledoc """
  Service for aggregating killmail data into statistics.
  This service generates daily, weekly, and monthly statistics for tracked characters
  based on their killmail history.
  """

  require Ash.Query
  require Logger

  alias Ash.Query
  alias WandererNotifier.Config.Timing
  alias WandererNotifier.Logger, as: AppLogger
  alias WandererNotifier.Resources.Api
  alias WandererNotifier.Resources.Killmail
  alias WandererNotifier.Resources.KillmailStatistic
  alias WandererNotifier.Resources.TrackedCharacter

  @doc """
  Aggregate killmail data into statistics for all tracked characters.

  ## Parameters
    - period_type: The type of period to aggregate (:daily, :weekly, or :monthly)
    - date: The date for which to generate statistics (defaults to today)

  ## Returns
    - :ok if successful
    - {:error, reason} if aggregation fails
  """
  def aggregate_statistics(period_type \\ :daily, date \\ nil) do
    date = date || Date.utc_today()

    # Get date ranges for the specified period
    {period_start, period_end} = get_period_range(period_type, date)

    AppLogger.persistence_info(
      "Starting aggregation",
      period_type: period_type,
      period_start: "#{period_start}",
      period_end: "#{period_end}"
    )

    # Get all tracked characters
    case get_tracked_characters() do
      [] ->
        AppLogger.persistence_info(
          "[KillmailAggregation] No tracked characters found, skipping aggregation"
        )

        :ok

      tracked_characters ->
        # Process each character and create/update statistics
        results =
          Enum.map(tracked_characters, fn character ->
            aggregate_character_statistics(character, period_type, period_start, period_end)
          end)

        # Log results
        success_count = Enum.count(results, &(&1 == :ok))

        AppLogger.persistence_info(
          "Completed aggregation",
          success_count: success_count,
          total_count: length(results)
        )

        :ok
    end
  rescue
    e ->
      AppLogger.persistence_error(
        "[KillmailAggregation] Error during aggregation: #{Exception.message(e)}"
      )

      AppLogger.persistence_debug("[KillmailAggregation] #{Exception.format_stacktrace()}")
      {:error, e}
  end

  @doc """
  Clean up old individual killmail records based on retention policy.

  ## Parameters
    - retention_days: Number of days to keep individual killmail records

  ## Returns
    - {deleted_count, error_count} - Counts of deleted records and errors
  """
  def cleanup_old_killmails(retention_days \\ nil) do
    retention_days = retention_days || get_retention_period()

    # Calculate cutoff date
    cutoff_date = Date.add(Date.utc_today(), -retention_days)
    cutoff_datetime = DateTime.new!(cutoff_date, ~T[00:00:00.000], "Etc/UTC")

    AppLogger.persistence_info(
      "[KillmailAggregation] Cleaning up killmails older than #{cutoff_date}"
    )

    # Query killmails older than the cutoff date
    old_killmails =
      Killmail
      |> Query.filter(kill_time: [<: cutoff_datetime])
      |> Query.load([:id, :killmail_id, :kill_time])
      |> Query.data_layer_query()

    # Count how many records we're going to delete
    count = Enum.count(old_killmails)

    if count > 0 do
      AppLogger.persistence_info("[KillmailAggregation] Found #{count} killmails to delete")

      # Delete the old killmails in batches
      delete_in_batches(old_killmails)
    else
      AppLogger.persistence_info(
        "[KillmailAggregation] No killmails found older than the cutoff date"
      )

      {0, 0}
    end
  rescue
    e ->
      AppLogger.persistence_error(
        "[KillmailAggregation] Error during cleanup: #{Exception.message(e)}"
      )

      AppLogger.persistence_debug("[KillmailAggregation] #{Exception.format_stacktrace()}")
      {0, 1}
  end

  # Get date range for a specific period type
  defp get_period_range(:daily, date) do
    {date, date}
  end

  defp get_period_range(:weekly, date) do
    # Get the start of the week (Monday)
    days_since_monday = Date.day_of_week(date) - 1
    start_date = Date.add(date, -days_since_monday)
    # End of week is 6 days later (Sunday)
    end_date = Date.add(start_date, 6)
    {start_date, end_date}
  end

  defp get_period_range(:monthly, date) do
    # Start of month
    start_date = %{date | day: 1}
    # End of month - calculate days in month
    days_in_month = Date.days_in_month(date)
    end_date = %{date | day: days_in_month}
    {start_date, end_date}
  end

  # Get all tracked characters
  defp get_tracked_characters do
    case TrackedCharacter
         |> Query.load([:character_id, :character_name])
         |> Api.read() do
      {:ok, characters} -> characters
      _ -> []
    end
  end

  # Aggregate statistics for a single character
  defp aggregate_character_statistics(character, period_type, period_start, period_end) do
    character_id = character.character_id

    AppLogger.persistence_info(
      "Processing character statistics",
      character_name: character.character_name,
      character_id: character_id
    )

    # Convert dates to datetime ranges for querying
    start_datetime = DateTime.new!(period_start, ~T[00:00:00.000], "Etc/UTC")
    end_datetime = DateTime.new!(period_end, ~T[23:59:59.999], "Etc/UTC")

    # Find and process all kills for this character in the date range
    killmails = fetch_character_killmails(character, character_id, start_datetime, end_datetime)

    # Calculate statistics
    stats = calculate_statistics(killmails)

    # Log statistics summary
    log_character_statistics(character, stats)

    # Update or create statistics record
    save_character_statistics(
      character,
      stats,
      period_type,
      period_start,
      period_end,
      character_id
    )
  rescue
    e ->
      AppLogger.persistence_error(
        "Error aggregating character statistics",
        character_name: character.character_name,
        error: Exception.message(e)
      )

      AppLogger.persistence_debug("Error stacktrace: #{Exception.format_stacktrace()}")
      {:error, e}
  end

  # Fetch killmails for a character within a specific time period
  defp fetch_character_killmails(character, character_id, start_datetime, end_datetime) do
    result =
      Killmail
      |> Query.filter(related_character_id: character_id)
      |> Query.filter(kill_time: [>=: start_datetime])
      |> Query.filter(kill_time: [<=: end_datetime])
      |> Query.load([
        :killmail_id,
        :kill_time,
        :character_role,
        :total_value,
        :region_name,
        :ship_type_id,
        :ship_type_name,
        :zkb_data,
        :victim_data,
        :attacker_data
      ])
      |> Api.read()

    case result do
      {:ok, records} ->
        AppLogger.persistence_info(
          "Successfully queried killmails",
          count: length(records),
          character_name: character.character_name
        )

        records

      error ->
        AppLogger.persistence_error(
          "Error querying killmails",
          character_name: character.character_name,
          error: inspect(error)
        )

        []
    end
  end

  # Log statistics summary for a character
  defp log_character_statistics(character, stats) do
    Logger.info(
      "[KillmailAggregation] Statistics for #{character.character_name}: " <>
        "kills=#{stats.kills_count}, deaths=#{stats.deaths_count}, " <>
        "solo_kills=#{stats.solo_kills_count}, final_blows=#{stats.final_blows_count}, " <>
        "isk_destroyed=#{Decimal.to_string(stats.isk_destroyed)}, " <>
        "regions=#{map_size(stats.region_activity)}, ships=#{map_size(stats.ship_usage)}"
    )
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
        Logger.error(
          "[KillmailAggregation] Error finding existing stats for character #{character_name}: #{inspect(error)}"
        )

        nil
    end
  end

  # Update existing statistics record
  defp update_existing_statistics(existing_stat, statistic_attrs, character_name) do
    AppLogger.persistence_info(
      "[KillmailAggregation] Updating existing statistics for #{character_name}"
    )

    result =
      Api.update(
        KillmailStatistic,
        existing_stat.id,
        statistic_attrs,
        action: :update
      )

    case result do
      {:ok, _updated} ->
        AppLogger.persistence_info(
          "[KillmailAggregation] Successfully updated statistics for #{character_name}"
        )

        :ok

      error ->
        AppLogger.persistence_error(
          "[KillmailAggregation] Error updating statistics: #{inspect(error)}"
        )

        {:error, error}
    end
  end

  # Create new statistics record
  defp create_new_statistics(statistic_attrs, character_name) do
    AppLogger.persistence_info(
      "[KillmailAggregation] Creating new statistics for #{character_name}"
    )

    result =
      Api.create(KillmailStatistic, statistic_attrs, action: :create)

    case result do
      {:ok, _created} ->
        AppLogger.persistence_info(
          "[KillmailAggregation] Successfully created statistics for #{character_name}"
        )

        :ok

      error ->
        AppLogger.persistence_error(
          "[KillmailAggregation] Error creating statistics: #{inspect(error)}"
        )

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
    Timing.get_persistence_config()
    |> Keyword.get(:retention_period_days, 180)
  end
end
