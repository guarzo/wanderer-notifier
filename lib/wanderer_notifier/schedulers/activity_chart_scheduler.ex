defmodule WandererNotifier.Schedulers.ActivityChartScheduler do
  @moduledoc """
  Scheduler for activity chart generation.
  """

  use WandererNotifier.Schedulers.IntervalScheduler,
    name: __MODULE__

  # Interval is now configured via the Timings module

  alias WandererNotifier.ChartService.ActivityChartAdapter
  alias WandererNotifier.Config.Features
  alias WandererNotifier.Config.Timings
  alias WandererNotifier.Logger.Logger, as: AppLogger

  @impl true
  def enabled? do
    Features.map_charts_enabled?()
  end

  @impl true
  def execute(state) do
    if enabled?() do
      AppLogger.scheduler_info("#{inspect(__MODULE__)}: Generating activity charts")

      case ActivityChartAdapter.update_activity_charts() do
        {:ok, count} ->
          AppLogger.scheduler_info("#{inspect(__MODULE__)}: Generated #{count} activity charts")
          {:ok, :completed, state}

        {:error, :feature_disabled} ->
          AppLogger.scheduler_info("#{inspect(__MODULE__)}: Activity charts feature disabled")
          {:ok, :skipped, Map.put(state, :reason, :feature_disabled)}

        {:error, reason} ->
          AppLogger.scheduler_error("#{inspect(__MODULE__)}: Failed to generate activity charts",
            error: inspect(reason)
          )

          {:error, reason, state}
      end
    else
      AppLogger.scheduler_info(
        "#{inspect(__MODULE__)}: Skipping activity chart generation (disabled)"
      )

      {:ok, :skipped, Map.put(state, :reason, :scheduler_disabled)}
    end
  end

  @impl true
  def get_config do
    %{
      type: :interval,
      interval: Timings.activity_chart_interval(),
      description: "Character activity chart generation"
    }
  end
end
