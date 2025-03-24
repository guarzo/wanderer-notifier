defmodule WandererNotifier.Services.Maintenance do
  @moduledoc """
  Handles periodic maintenance tasks for the application.
  Includes system and character updates and health checks.
  """
  use GenServer
  require Logger
  alias WandererNotifier.Services.Maintenance.Scheduler
  alias WandererNotifier.Logger, as: AppLogger

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    # Schedule the first tick
    schedule_tick()
    # Initialize state with the current timestamp
    current_time = :os.system_time(:second)

    # Wrap the initial checks in a try/catch to prevent crashes if license service is down
    state = %{
      service_start_time: current_time,
      last_systems_update: current_time,
      last_characters_update: current_time,
      last_status_time: current_time,
      systems_count: 0,
      characters_count: 0
    }

    # Convert state to keyword list for logging
    state_kw = Enum.map(state, fn {k, v} -> {k, v} end)
    AppLogger.maintenance_info("Starting maintenance service", state_kw)

    # Perform initial checks safely
    try do
      Scheduler.do_initial_checks(state)
    rescue
      e ->
        AppLogger.maintenance_error("Initial maintenance checks failed", error: inspect(e))
        # Return the base state if checks fail
        state
    catch
      type, error ->
        AppLogger.maintenance_error("Initial maintenance error caught",
          error_type: inspect(type),
          error: inspect(error)
        )

        state
    end

    {:ok, state}
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
    Process.send_after(self(), :tick, WandererNotifier.Config.Timings.maintenance_interval())
  end
end
