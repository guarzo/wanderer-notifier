defmodule WandererNotifier.Service.Maintenance do
  @moduledoc """
  Maintenance service that runs periodic tasks to keep the application state up to date.
  """
  use GenServer
  require Logger
  alias WandererNotifier.Maintenance.Scheduler

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    # Schedule the first tick
    schedule_tick()
    # Initialize state
    state = Scheduler.do_initial_checks(%{
      service_start_time: :os.system_time(:second),
      last_systems_update: nil,
      last_characters_update: nil,
      systems_count: 0,
      characters_count: 0
    })
    {:ok, state}
  end

  @impl true
  def handle_info(:tick, state) do
    # Schedule the next tick
    schedule_tick()
    # Run the maintenance tasks
    new_state = Scheduler.tick(state)
    {:noreply, new_state}
  end

  defp schedule_tick do
    # Schedule the next tick after the maintenance interval
    Process.send_after(self(), :tick, WandererNotifier.Config.Timings.maintenance_interval())
  end
end
