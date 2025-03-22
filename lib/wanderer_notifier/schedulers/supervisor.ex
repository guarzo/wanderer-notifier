defmodule WandererNotifier.Schedulers.Supervisor do
  @moduledoc """
  Supervisor for all schedulers in the application.

  This module supervises the scheduler registry and all scheduler processes.
  """

  use Supervisor
  require Logger

  def start_link(opts \\ []) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    Logger.info("Starting Scheduler Supervisor...")

    # Define the scheduler registry
    registry = {WandererNotifier.Schedulers.Registry, []}

    # Define all schedulers to be supervised
    schedulers = [
      {WandererNotifier.Schedulers.ActivityChartScheduler, []},
      {WandererNotifier.Schedulers.CharacterUpdateScheduler, []},
      {WandererNotifier.Schedulers.SystemUpdateScheduler, []}
    ]

    # Add persistence-related schedulers if persistence is enabled
    schedulers =
      if persistence_enabled?() do
        Logger.info("Persistence enabled, adding killmail schedulers")

        schedulers ++
          [
            {WandererNotifier.Schedulers.KillmailAggregationScheduler, []},
            {WandererNotifier.Schedulers.KillmailRetentionScheduler, []},
            {WandererNotifier.Schedulers.KillmailChartScheduler, []}
          ]
      else
        schedulers
      end

    children = [registry | schedulers]

    # Start all children with a one_for_one strategy
    Supervisor.init(children, strategy: :one_for_one)
  end

  @doc """
  Adds a scheduler dynamically to the supervision tree.
  """
  def add_scheduler(scheduler_module) do
    # Add the scheduler to the supervision tree
    case Supervisor.start_child(__MODULE__, {scheduler_module, []}) do
      {:ok, _pid} ->
        # Register the scheduler with the registry
        WandererNotifier.Schedulers.Registry.register(scheduler_module)
        :ok

      {:error, {:already_started, _pid}} ->
        # Scheduler already started
        :ok

      {:error, reason} ->
        Logger.error("Failed to start scheduler #{inspect(scheduler_module)}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # Check if persistence is enabled
  defp persistence_enabled? do
    Application.get_env(:wanderer_notifier, :persistence, [])
    |> Keyword.get(:enabled, false)
  end
end
