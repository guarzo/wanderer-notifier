defmodule WandererNotifier.Schedulers.SystemUpdateScheduler do
  @moduledoc """
  Scheduler for updating solar system data from the Map API.

  This scheduler periodically fetches and updates solar system data,
  detecting and notifying about new systems.
  """

  require WandererNotifier.Schedulers.Factory
  require Logger
  alias WandererNotifier.Logger, as: AppLogger

  alias WandererNotifier.Api.Map.SystemsClient
  alias WandererNotifier.Core.Config.Timings

  # Get the default interval from Timings module
  @default_interval Timings.system_update_scheduler_interval()

  # Create an interval-based scheduler with specific configuration
  WandererNotifier.Schedulers.Factory.create_scheduler(__MODULE__,
    type: :interval,
    default_interval: @default_interval,
    enabled_check: &WandererNotifier.Core.Config.map_charts_enabled?/0
  )

  @impl true
  def execute(state) do
    AppLogger.scheduler_info("Executing solar system data update")

    result = SystemsClient.update_systems()

    case result do
      {:ok, systems} ->
        AppLogger.scheduler_info("Successfully updated #{length(systems)} solar systems")
        {:ok, %{system_count: length(systems)}, state}

      {:error, reason} ->
        AppLogger.scheduler_error("Failed to update solar systems: #{inspect(reason)}")
        {:error, reason, state}
    end
  end
end
