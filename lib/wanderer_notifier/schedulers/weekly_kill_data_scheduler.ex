defmodule WandererNotifier.Schedulers.WeeklyKillDataScheduler do
  @moduledoc """
  Scheduler for fetching character kill data weekly.
  Runs the kills service load kill data once per week.
  """

  use WandererNotifier.Schedulers.IntervalScheduler,
    name: __MODULE__

  alias WandererNotifier.Api.Character.KillsService
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
      AppLogger.scheduler_info("#{inspect(__MODULE__)}: Running weekly character kill data fetch")

      # Use a higher limit for weekly batch processing
      limit = 100
      page = 1

      # Fetch and persist kills for all tracked characters
      case KillsService.fetch_and_persist_all_tracked_character_kills(limit, page) do
        {:ok, result} ->
          AppLogger.scheduler_info(
            "#{inspect(__MODULE__)}: Successfully fetched character kill data",
            %{
              processed: result.processed,
              persisted: result.persisted,
              characters: result.characters
            }
          )

          {:ok, :completed, state}

        {:error, :no_tracked_characters} ->
          AppLogger.scheduler_info("#{inspect(__MODULE__)}: No tracked characters found")
          {:ok, :skipped, Map.put(state, :reason, :no_tracked_characters)}

        {:error, reason} ->
          AppLogger.scheduler_error("#{inspect(__MODULE__)}: Failed to fetch character kill data",
            error: inspect(reason)
          )

          {:error, reason, state}
      end
    else
      AppLogger.scheduler_info(
        "#{inspect(__MODULE__)}: Skipping weekly kill data fetch (disabled)"
      )

      {:ok, :skipped, Map.put(state, :reason, :scheduler_disabled)}
    end
  end

  @impl true
  def get_config do
    %{
      type: :interval,
      interval: Timings.weekly_kill_data_fetch_interval(),
      description: "Weekly character kill data fetch"
    }
  end
end
