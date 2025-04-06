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

  alias WandererNotifier.Config.Timings
  alias WandererNotifier.Logger.Logger, as: AppLogger
  alias WandererNotifier.Resources.KillmailAggregation

  # Use the interval scheduler as our base
  use WandererNotifier.Schedulers.IntervalScheduler,
    name: __MODULE__

  @impl true
  def execute(state) do
    AppLogger.scheduler_info("Running killmail retention job")

    retention_days = get_retention_days()

    AppLogger.scheduler_info("Cleaning killmails older than #{retention_days} days")

    case KillmailAggregation.clean_old_killmails(retention_days) do
      {:ok, %{deleted: deleted_count, errors: error_count}} ->
        AppLogger.scheduler_info("Killmail retention job complete", %{
          deleted_count: deleted_count,
          error_count: error_count
        })

        # Return the proper tuple format expected by IntervalScheduler
        {:ok, %{deleted_count: deleted_count, error_count: error_count}, state}

      {:error, reason} ->
        AppLogger.scheduler_error("Killmail retention job failed", %{
          reason: inspect(reason)
        })

        {:error, reason, state}
    end
  rescue
    e ->
      AppLogger.scheduler_error(
        "#{inspect(@scheduler_name)}: Error during killmail retention: #{Exception.message(e)}"
      )

      AppLogger.scheduler_debug(Exception.format_stacktrace())
      {:error, e, state}
  end

  @impl true
  def get_config do
    %{
      type: :interval,
      interval: Timings.killmail_retention_interval(),
      description: "Cleanup old killmail data based on retention policy"
    }
  end

  defp get_retention_days do
    Timings.persistence_config() |> Keyword.get(:retention_period_days, 180)
  end
end
