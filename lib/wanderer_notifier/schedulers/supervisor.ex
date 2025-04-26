defmodule WandererNotifier.Schedulers.Supervisor do
  @moduledoc """
  Supervisor for scheduler modules.
  Manages the lifecycle of all scheduler processes.
  """

  use Supervisor
  alias WandererNotifier.Logger.Logger, as: AppLogger
  alias WandererNotifier.Logger.StartupTracker
  alias WandererNotifier.Schedulers
  alias WandererNotifier.Schedulers.Registry

  def start_link(opts \\ []) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    # Begin the scheduler phase in the startup tracker
    start_scheduler_phase()

    AppLogger.scheduler_debug("Starting Scheduler Supervisor...")

    # Define the scheduler registry
    registry = {Registry, []}

    # Define core schedulers and build complete list
    core_schedulers = define_core_schedulers()

    # Create children list with consolidated logging
    children = [registry | core_schedulers]

    # Single consolidated log message for all schedulers
    AppLogger.startup_info("⏰ Scheduler system ready (#{length(core_schedulers)} schedulers)")

    # Start all children with a one_for_one strategy
    Supervisor.init(children, strategy: :one_for_one)
  end

  # Start the scheduler phase in the startup tracker
  defp start_scheduler_phase do
    if Process.get(:startup_tracker) do
      StartupTracker.begin_phase(:schedulers, "Initializing schedulers")
    end
  end

  # Define the core schedulers
  defp define_core_schedulers do
    schedulers = [
      {Schedulers.SystemUpdateScheduler, []},
      {Schedulers.CharacterUpdateScheduler, []},
      {Schedulers.ServiceStatusScheduler, []}
    ]

    # Track core schedulers
    try do
      StartupTracker.record_event(:scheduler_setup, %{
        core_schedulers: length(schedulers)
      })
    rescue
      _ -> :ok
    end

    schedulers
  end

  @doc """
  Adds a scheduler dynamically to the supervision tree.
  """
  def add_scheduler(scheduler_module) do
    # Add the scheduler to the supervision tree
    case Supervisor.start_child(__MODULE__, {scheduler_module, []}) do
      {:ok, _pid} ->
        # Register the scheduler with the registry
        Registry.register(scheduler_module)
        :ok

      {:error, {:already_started, _pid}} ->
        # Scheduler already started
        :ok

      {:error, reason} ->
        AppLogger.scheduler_error(
          "Failed to start scheduler #{inspect(scheduler_module)}: #{inspect(reason)}"
        )

        {:error, reason}
    end
  end
end
