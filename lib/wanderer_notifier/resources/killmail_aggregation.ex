defmodule WandererNotifier.Resources.KillmailAggregation do
  @moduledoc """
  Service for aggregating killmail data into statistics.
  This service generates daily, weekly, and monthly statistics for tracked characters
  based on their killmail history.
  """

  require Logger
  require Ash.Query
  alias WandererNotifier.Resources.KillmailStatistic
  alias WandererNotifier.Resources.Killmail
  alias WandererNotifier.Resources.TrackedCharacter
  alias Ash.Query

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
    try do
      date = date || Date.utc_today()

      # Get date ranges for the specified period
      {period_start, period_end} = get_period_range(period_type, date)

      Logger.info(
        "[KillmailAggregation] Starting aggregation for #{period_type} period: #{period_start} to #{period_end}"
      )

      # Get all tracked characters
      case get_tracked_characters() do
        [] ->
          Logger.info("[KillmailAggregation] No tracked characters found, skipping aggregation")
          :ok

        tracked_characters ->
          # Process each character and create/update statistics
          results =
            Enum.map(tracked_characters, fn character ->
              aggregate_character_statistics(character, period_type, period_start, period_end)
            end)

          # Log results
          success_count = Enum.count(results, &(&1 == :ok))

          Logger.info(
            "[KillmailAggregation] Completed aggregation: #{success_count}/#{length(results)} successful"
          )

          :ok
      end
    rescue
      e ->
        Logger.error("[KillmailAggregation] Error during aggregation: #{Exception.message(e)}")
        Logger.debug("[KillmailAggregation] #{Exception.format_stacktrace()}")
        {:error, e}
    end
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

    Logger.info("[KillmailAggregation] Cleaning up killmails older than #{cutoff_date}")

    # Find killmails older than the cutoff date
    try do
      # Query killmails older than the cutoff date
      old_killmails =
        Killmail
        |> Query.filter(kill_time: [<: cutoff_datetime])
        |> Query.load([:id, :killmail_id, :kill_time])
        |> Query.data_layer_query()

      # Count how many records we're going to delete
      count = Enum.count(old_killmails)

      if count > 0 do
        Logger.info("[KillmailAggregation] Found #{count} killmails to delete")

        # Delete the old killmails in batches
        delete_in_batches(old_killmails)
      else
        Logger.info("[KillmailAggregation] No killmails found older than the cutoff date")
        {0, 0}
      end
    rescue
      e ->
        Logger.error("[KillmailAggregation] Error during cleanup: #{Exception.message(e)}")
        Logger.debug("[KillmailAggregation] #{Exception.format_stacktrace()}")
        {0, 1}
    end
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
    TrackedCharacter
    |> Query.load([:character_id, :character_name])
    |> WandererNotifier.Resources.Api.read()
  end

  # Aggregate statistics for a single character
  defp aggregate_character_statistics(character, period_type, period_start, period_end) do
    character_id = character.character_id

    Logger.info(
      "[KillmailAggregation] Processing statistics for character #{character.character_name} (#{character_id})"
    )

    # Convert dates to datetime ranges for querying
    start_datetime = DateTime.new!(period_start, ~T[00:00:00.000], "Etc/UTC")
    end_datetime = DateTime.new!(period_end, ~T[23:59:59.999], "Etc/UTC")

    try do
      # Find all kills for this character in the date range
      killmails =
        Killmail
        |> Query.filter(related_character_id: character_id)
        |> Query.filter(kill_time: [>=: start_datetime])
        |> Query.filter(kill_time: [<=: end_datetime])
        |> Query.load([
          :id,
          :killmail_id,
          :kill_time,
          :character_role,
          :solar_system_name,
          :region_name,
          :total_value,
          :ship_type_id,
          :ship_type_name
        ])
        |> WandererNotifier.Resources.Api.read()

      Logger.info(
        "[KillmailAggregation] Found #{length(killmails)} killmails for character #{character.character_name}"
      )

      # Calculate statistics
      stats = calculate_statistics(killmails)

      # Try to find an existing statistic record for this period
      existing_stat =
        KillmailStatistic
        |> Query.filter(character_id: character_id)
        |> Query.filter(period_type: period_type)
        |> Query.filter(period_start: period_start)
        |> WandererNotifier.Resources.Api.read()
        |> List.first()

      # Create the statistics record or update existing
      statistic_attrs = %{
        period_type: period_type,
        period_start: period_start,
        period_end: period_end,
        character_id: character_id,
        character_name: character.character_name,
        kills_count: stats.kills_count,
        deaths_count: stats.deaths_count,
        isk_destroyed: stats.isk_destroyed,
        isk_lost: stats.isk_lost,
        region_activity: stats.region_activity,
        ship_usage: stats.ship_usage,
        top_victim_corps: stats.top_victim_corps,
        top_victim_ships: stats.top_victim_ships,
        detailed_ship_usage: stats.detailed_ship_usage
      }

      if existing_stat do
        Logger.info(
          "[KillmailAggregation] Updating existing statistics for #{character.character_name}"
        )

        WandererNotifier.Resources.Api.update(KillmailStatistic, existing_stat.id, statistic_attrs, action: :update)
      else
        Logger.info(
          "[KillmailAggregation] Creating new statistics for #{character.character_name}"
        )

        WandererNotifier.Resources.Api.create(KillmailStatistic, statistic_attrs, action: :create)
      end

      :ok
    rescue
      e ->
        Logger.error(
          "[KillmailAggregation] Error aggregating statistics for character #{character.character_name}: #{Exception.message(e)}"
        )

        Logger.debug("[KillmailAggregation] #{Exception.format_stacktrace()}")
        {:error, e}
    end
  end

  # Calculate statistics from killmails
  defp calculate_statistics(killmails) do
    # Initialize empty statistics
    stats = %{
      kills_count: 0,
      deaths_count: 0,
      isk_destroyed: Decimal.new(0),
      isk_lost: Decimal.new(0),
      region_activity: %{},
      ship_usage: %{},
      top_victim_corps: %{},
      top_victim_ships: %{},
      detailed_ship_usage: %{}
    }

    # Process each killmail and aggregate statistics
    Enum.reduce(killmails, stats, fn killmail, acc ->
      # Determine if this is a kill or death
      case killmail.character_role do
        :attacker ->
          # This is a kill
          kills_count = acc.kills_count + 1
          isk_destroyed = Decimal.add(acc.isk_destroyed, killmail.total_value || Decimal.new(0))

          # Update region activity
          region_activity = update_region_count(acc.region_activity, killmail.region_name)

          # Update ship usage
          ship_usage = update_ship_usage(acc.ship_usage, killmail.ship_type_name)

          # Update victim information from victim_data
          victim_data = killmail.victim_data || %{}

          # Extract victim corporation
          victim_corp = Map.get(victim_data, "corporation_name", "Unknown")
          top_victim_corps = update_count_map(acc.top_victim_corps, victim_corp)

          # Extract victim ship
          victim_ship = Map.get(victim_data, "ship_type_name", "Unknown")
          top_victim_ships = update_count_map(acc.top_victim_ships, victim_ship)

          # Update detailed ship usage (which ship was used to kill which ship)
          detailed_usage_key = "#{killmail.ship_type_name || "Unknown"} → #{victim_ship}"
          detailed_ship_usage = update_count_map(acc.detailed_ship_usage, detailed_usage_key)

          # Return updated statistics
          %{
            acc
            | kills_count: kills_count,
              isk_destroyed: isk_destroyed,
              region_activity: region_activity,
              ship_usage: ship_usage,
              top_victim_corps: top_victim_corps,
              top_victim_ships: top_victim_ships,
              detailed_ship_usage: detailed_ship_usage
          }

        :victim ->
          # This is a death
          deaths_count = acc.deaths_count + 1
          isk_lost = Decimal.add(acc.isk_lost, killmail.total_value || Decimal.new(0))

          # Return updated statistics
          %{
            acc
            | deaths_count: deaths_count,
              isk_lost: isk_lost
          }
      end
    end)
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
        WandererNotifier.Resources.Api.destroy(Killmail, killmail.id)
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
    Application.get_env(:wanderer_notifier, :persistence, [])
    |> Keyword.get(:retention_period_days, 180)
  end
end
