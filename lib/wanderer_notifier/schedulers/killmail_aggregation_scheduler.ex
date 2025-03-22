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
  alias WandererNotifier.Resources.KillmailAggregation

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
    if persistence_enabled?() do
      Logger.info("#{inspect(@scheduler_name)}: Running killmail aggregation")

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

      # Return the aggregation results
      {:ok, %{daily: daily_result, weekly: weekly_result, monthly: monthly_result}, state}
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

      Logger.debug(Exception.format_stacktrace())
      {:error, e, state}
  end

  # Run aggregation for a specific period
  defp aggregate_for_period(period_type, date) do
    Logger.info("#{inspect(@scheduler_name)}: Running #{period_type} aggregation for #{date}")

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
    # Log daily result
    case daily do
      {:ok, _} ->
        Logger.info("#{inspect(@scheduler_name)}: Daily aggregation completed successfully")

      {:error, _, reason} ->
        Logger.error("#{inspect(@scheduler_name)}: Daily aggregation failed: #{inspect(reason)}")

      :skipped ->
        Logger.info("#{inspect(@scheduler_name)}: Daily aggregation skipped")
    end

    # Log weekly result
    case weekly do
      {:ok, _} ->
        Logger.info("#{inspect(@scheduler_name)}: Weekly aggregation completed successfully")

      {:error, _, reason} ->
        Logger.error("#{inspect(@scheduler_name)}: Weekly aggregation failed: #{inspect(reason)}")

      :skipped ->
        Logger.info("#{inspect(@scheduler_name)}: Weekly aggregation skipped (not end of week)")
    end

    # Log monthly result
    case monthly do
      {:ok, _} ->
        Logger.info("#{inspect(@scheduler_name)}: Monthly aggregation completed successfully")

      {:error, _, reason} ->
        Logger.error(
          "#{inspect(@scheduler_name)}: Monthly aggregation failed: #{inspect(reason)}"
        )

      :skipped ->
        Logger.info("#{inspect(@scheduler_name)}: Monthly aggregation skipped (not end of month)")
    end
  end

  # Check if persistence is enabled
  defp persistence_enabled? do
    Application.get_env(:wanderer_notifier, :persistence, [])
    |> Keyword.get(:enabled, false)
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
