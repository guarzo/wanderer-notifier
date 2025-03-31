defmodule WandererNotifier.Core.Maintenance.Service do
  @moduledoc """
  Handles periodic maintenance tasks for the application.
  Includes system and character updates and health checks.
  """
  use GenServer
  require Logger
  alias WandererNotifier.Config.Timings
  alias WandererNotifier.Core.Logger, as: AppLogger
  alias WandererNotifier.Core.Maintenance.Scheduler

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    # Schedule the first tick
    schedule_tick()
    # Initialize state with the current timestamp
    current_time = :os.system_time(:second)

    # Initialize base state
    base_state = %{
      service_start_time: current_time,
      last_systems_update: current_time,
      last_characters_update: current_time,
      last_status_time: current_time,
      systems_count: 0,
      characters_count: 0
    }

    # Convert state to keyword list for logging
    state_kw = Enum.map(base_state, fn {k, v} -> {k, v} end)
    AppLogger.maintenance_info("Starting maintenance service", state_kw)

    # Perform initial checks safely
    try do
      final_state = Scheduler.do_initial_checks(base_state)
      {:ok, final_state}
    rescue
      e ->
        AppLogger.maintenance_error("Initial maintenance checks failed", error: inspect(e))
        # Return the base state if checks fail
        {:ok, base_state}
    catch
      type, error ->
        AppLogger.maintenance_error("Initial maintenance error caught",
          error_type: inspect(type),
          error: inspect(error)
        )

        {:ok, base_state}
    end
  end

  @impl true
  def handle_info(:tick, state) do
    # Schedule the next tick
    schedule_tick()

    AppLogger.maintenance_debug("Running maintenance tick",
      uptime_seconds: :os.system_time(:second) - state.service_start_time,
      systems_count: state.systems_count,
      characters_count: state.characters_count
    )

    # Run the maintenance tasks safely
    new_state =
      try do
        Scheduler.tick(state)
      rescue
        e ->
          AppLogger.maintenance_error("Maintenance tick failed", error: inspect(e))
          state
      catch
        type, error ->
          AppLogger.maintenance_error("Maintenance tick error caught",
            error_type: inspect(type),
            error: inspect(error)
          )

          state
      end

    {:noreply, new_state}
  end

  defp schedule_tick do
    # Schedule the next tick after the maintenance interval
    Process.send_after(self(), :tick, Timings.maintenance_interval())
  end
end
