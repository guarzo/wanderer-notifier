defmodule WandererNotifier.Schedulers.KillValidationChartScheduler do
  @moduledoc """
  Scheduler for kill validation chart generation.
  """

  use WandererNotifier.Schedulers.IntervalScheduler,
    name: __MODULE__

  alias WandererNotifier.ChartService.KillmailChartAdapter
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
      AppLogger.scheduler_info("#{inspect(__MODULE__)}: Generating kill validation chart")

      case KillmailChartAdapter.schedule_kill_validation_chart() do
        :ok ->
          AppLogger.scheduler_info("#{inspect(__MODULE__)}: Generated kill validation chart")
          {:ok, :completed, state}

        {:error, :feature_disabled} ->
          AppLogger.scheduler_info("#{inspect(__MODULE__)}: Kill charts feature disabled")
          {:ok, :skipped, Map.put(state, :reason, :feature_disabled)}

        {:error, reason} ->
          AppLogger.scheduler_error(
            "#{inspect(__MODULE__)}: Failed to generate kill validation chart",
            error: inspect(reason)
          )

          {:error, reason, state}
      end
    else
      AppLogger.scheduler_info(
        "#{inspect(__MODULE__)}: Skipping kill validation chart generation (disabled)"
      )

      {:ok, :skipped, Map.put(state, :reason, :scheduler_disabled)}
    end
  end

  @impl true
  def get_config do
    %{
      type: :interval,
      # Run every 60 minutes
      interval: :timer.minutes(60),
      description: "Kill validation chart generation"
    }
  end
end
