defmodule WandererNotifier.Services.Maintenance do
  @moduledoc """
  Handles periodic maintenance tasks for the application.
  Includes system and character updates and health checks.
  """
  use GenServer
  require Logger
  alias WandererNotifier.Services.Maintenance.Scheduler

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

    # Perform initial checks safely
    try do
      Scheduler.do_initial_checks(state)
    rescue
      e ->
        Logger.error("Error during initial maintenance checks: #{inspect(e)}")
        # Return the base state if checks fail
        state
    catch
      type, error ->
        Logger.error("Error during initial maintenance checks: #{inspect(type)}, #{inspect(error)}")
        state
    end

    {:ok, state}
  end

  @impl true
  def handle_info(:tick, state) do
    # Schedule the next tick
    schedule_tick()

    # Run the maintenance tasks safely
    new_state = try do
      Scheduler.tick(state)
    rescue
      e ->
        Logger.error("Error during maintenance tick: #{inspect(e)}")
        state
    catch
      type, error ->
        Logger.error("Error during maintenance tick: #{inspect(type)}, #{inspect(error)}")
        state
    end

    {:noreply, new_state}
  end

  defp schedule_tick do
    # Schedule the next tick after the maintenance interval
    Process.send_after(self(), :tick, WandererNotifier.Config.Timings.maintenance_interval())
  end
end
