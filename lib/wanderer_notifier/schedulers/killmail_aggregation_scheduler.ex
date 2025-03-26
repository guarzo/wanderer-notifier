defmodule WandererNotifier.Schedulers.KillmailAggregationScheduler do
  @moduledoc """
  Scheduler for generating killmail statistics through aggregation.

  This scheduler runs daily to aggregate killmail data into statistics for each tracked character.
  It generates daily, weekly, and monthly statistics based on the schedule defined in configuration:

  ```
  config :wanderer_notifier, :persistence,
    aggregation_schedule: "0 0 * * *" # Daily at midnight
  ```
  """

  require Logger
  alias WandererNotifier.Logger, as: AppLogger
  alias WandererNotifier.Resources.KillmailAggregation
  alias WandererNotifier.Services.CharacterKillsService

  # Default to midnight (hour = 0, minute = 0)
  @default_hour 0
  @default_minute 0

  # Use the time scheduler as our base for running at a specific time each day
  use WandererNotifier.Schedulers.TimeScheduler,
    default_hour: @default_hour,
    default_minute: @default_minute,
    hour_env_var: :aggregation_schedule_hour,
    minute_env_var: :aggregation_schedule_minute

  @impl true
  def execute(state) do
    if kill_charts_enabled?() do
      AppLogger.scheduler_info("#{inspect(@scheduler_name)}: Running killmail aggregation")

      # First, fetch latest kills for all tracked characters
      fetch_result = fetch_latest_kills()

      # Get today's date
      today = Date.utc_today()

      # Run daily aggregation
      daily_result = aggregate_for_period(:daily, today)

      # Run weekly aggregation if today is Sunday (day 7)
      weekly_result =
        if Date.day_of_week(today) == 7 do
          aggregate_for_period(:weekly, today)
        else
          :skipped
        end

      # Run monthly aggregation if today is the last day of the month
      monthly_result =
        if today.day == Date.days_in_month(today) do
          aggregate_for_period(:monthly, today)
        else
          :skipped
        end

      # Log results
      log_aggregation_results(daily_result, weekly_result, monthly_result)

      # Return the aggregation results including fetch results
      {:ok,
       %{
         fetch: fetch_result,
         daily: daily_result,
         weekly: weekly_result,
         monthly: monthly_result
       }, state}
    else
      Logger.info(
        "#{inspect(@scheduler_name)}: Skipping killmail aggregation (persistence disabled)"
      )

      {:ok, :skipped, state}
    end
  rescue
    e ->
      Logger.error(
        "#{inspect(@scheduler_name)}: Error during killmail aggregation: #{Exception.message(e)}"
      )

      AppLogger.scheduler_debug(Exception.format_stacktrace())
      {:error, e, state}
  end

  # Fetch latest kills for all tracked characters
  defp fetch_latest_kills do
    AppLogger.scheduler_info(
      "#{inspect(@scheduler_name)}: Fetching latest character kills before aggregation"
    )

    # Set a reasonable limit for the scheduler (higher than the UI default)
    # Fetch up to 50 recent kills per character
    limit = 50

    try do
      case CharacterKillsService.fetch_and_persist_all_tracked_character_kills(limit, 1) do
        {:ok, stats} ->
          AppLogger.scheduler_info(
            "#{inspect(@scheduler_name)}: Successfully fetched kills before aggregation",
            characters: stats.characters,
            processed: stats.processed,
            persisted: stats.persisted
          )

          {:ok, stats}

        {:error, reason} ->
          AppLogger.scheduler_error(
            "#{inspect(@scheduler_name)}: Failed to fetch character kills",
            error: inspect(reason)
          )

          {:error, :fetch_failed, reason}
      end
    rescue
      e ->
        AppLogger.scheduler_error(
          "#{inspect(@scheduler_name)}: Exception during kill fetch: #{Exception.message(e)}"
        )

        {:error, :fetch_exception, e}
    end
  end

  # Run aggregation for a specific period
  defp aggregate_for_period(period_type, date) do
    AppLogger.scheduler_info(
      "#{inspect(@scheduler_name)}: Running #{period_type} aggregation for #{date}"
    )

    try do
      case KillmailAggregation.aggregate_statistics(period_type, date) do
        :ok -> {:ok, period_type}
        {:error, reason} -> {:error, period_type, reason}
      end
    rescue
      e ->
        Logger.error(
          "#{inspect(@scheduler_name)}: Error during #{period_type} aggregation: #{Exception.message(e)}"
        )

        {:error, period_type, e}
    end
  end

  # Log aggregation results
  defp log_aggregation_results(daily, weekly, monthly) do
    # Log each result type
    log_period_result(daily, "Daily")
    log_period_result(weekly, "Weekly", "(not end of week)")
    log_period_result(monthly, "Monthly", "(not end of month)")
  end

  # Helper function to log results for a specific period
  defp log_period_result(result, period_label, skip_reason \\ "") do
    case result do
      {:ok, _} ->
        Logger.info(
          "#{inspect(@scheduler_name)}: #{period_label} aggregation completed successfully"
        )

      {:error, _, reason} ->
        Logger.error(
          "#{inspect(@scheduler_name)}: #{period_label} aggregation failed: #{inspect(reason)}"
        )

      :skipped ->
        Logger.info(
          "#{inspect(@scheduler_name)}: #{period_label} aggregation skipped #{skip_reason}"
        )
    end
  end

  # Check if kill charts feature is enabled
  defp kill_charts_enabled? do
    WandererNotifier.Core.Config.kill_charts_enabled?()
  end

  @impl true
  def get_config do
    %{
      type: :time,
      hour: @default_hour,
      minute: @default_minute,
      description: "Aggregate killmail data into statistics"
    }
  end
end
