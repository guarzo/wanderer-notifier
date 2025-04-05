defmodule WandererNotifier.Schedulers.WeeklyKillChartScheduler do
  @moduledoc """
  Scheduler for sending weekly kill charts to Discord.
  """

  use WandererNotifier.Schedulers.IntervalScheduler,
    name: __MODULE__

  alias WandererNotifier.ChartService.KillmailChartAdapter
  alias WandererNotifier.Config.Config
  alias WandererNotifier.Config.Features
  alias WandererNotifier.Config.Timings
  alias WandererNotifier.Logger.Logger, as: AppLogger

  @impl true
  def enabled? do
    Features.kill_charts_enabled?()
  end

  @impl true
  def execute(state) do
    if enabled?() do
      AppLogger.scheduler_info("#{inspect(__MODULE__)}: Sending weekly kill charts to Discord")

      # Get the Discord channel ID for kill charts
      channel_id = Config.discord_channel_id_for(:kill_charts)

      # Get date range for the current week
      today = Date.utc_today()
      days_since_monday = Date.day_of_week(today) - 1
      date_from = Date.add(today, -days_since_monday)
      date_to = Date.add(date_from, 6)

      # Send the weekly kill charts
      case KillmailChartAdapter.send_weekly_kills_chart_to_discord(channel_id, date_from, date_to) do
        {:ok, _} ->
          AppLogger.scheduler_info("#{inspect(__MODULE__)}: Successfully sent weekly kill charts")
          {:ok, :completed, state}

        {:error, :feature_disabled} ->
          AppLogger.scheduler_info("#{inspect(__MODULE__)}: Kill charts feature disabled")
          {:ok, :skipped, Map.put(state, :reason, :feature_disabled)}

        {:error, reason} ->
          AppLogger.scheduler_error("#{inspect(__MODULE__)}: Failed to send weekly kill charts",
            error: inspect(reason)
          )

          {:error, reason, state}
      end
    else
      AppLogger.scheduler_info(
        "#{inspect(__MODULE__)}: Skipping weekly kill chart sending (disabled)"
      )

      {:ok, :skipped, Map.put(state, :reason, :scheduler_disabled)}
    end
  end

  @impl true
  def get_config do
    %{
      type: :interval,
      interval: Timings.weekly_kill_chart_interval(),
      description: "Weekly kill chart Discord sending"
    }
  end
end
