defmodule WandererNotifier.Schedulers.KillmailRetentionScheduler do
  @moduledoc """
  Scheduler for cleaning up old killmail data.

  This scheduler runs daily to clean up killmail records that are older than
  the configured retention period. The retention period is configurable via
  the application config:

  ```
  config :wanderer_notifier, :persistence,
    retention_period_days: 180
  ```
  """

  require Logger
  alias WandererNotifier.Config.Features
  alias WandererNotifier.Config.Timings
  alias WandererNotifier.Logger.Logger, as: AppLogger
  alias WandererNotifier.Resources.KillmailAggregation

  # Use the interval scheduler as our base
  use WandererNotifier.Schedulers.IntervalScheduler,
    default_interval: 24 * 60 * 60 * 1000

  @impl true
  def execute(state) do
    if Features.kill_charts_enabled?() do
      AppLogger.scheduler_info("#{inspect(@scheduler_name)}: Running killmail retention cleanup")

      # Get the configured retention period
      retention_days = Timings.persistence_config() |> Keyword.get(:retention_period_days, 180)

      # Run the cleanup operation
      {deleted_count, error_count} = KillmailAggregation.cleanup_old_killmails(retention_days)

      # Log the results
      if error_count > 0 do
        Logger.warning(
          "#{inspect(@scheduler_name)}: Cleanup completed with errors. Deleted: #{deleted_count}, Errors: #{error_count}",
          []
        )
      else
        Logger.info(
          "#{inspect(@scheduler_name)}: Cleanup completed successfully. Deleted: #{deleted_count} old killmails"
        )
      end

      {:ok, {deleted_count, error_count}, state}
    else
      Logger.info(
        "#{inspect(@scheduler_name)}: Skipping killmail retention (persistence disabled)"
      )

      {:ok, :skipped, state}
    end
  rescue
    e ->
      Logger.error(
        "#{inspect(@scheduler_name)}: Error during killmail retention: #{Exception.message(e)}"
      )

      AppLogger.scheduler_debug(Exception.format_stacktrace())
      {:error, e, state}
  end

  @impl true
  def get_config do
    %{
      type: :interval,
      interval: Timings.activity_chart_interval(),
      description: "Cleanup old killmail data based on retention policy"
    }
  end
end
