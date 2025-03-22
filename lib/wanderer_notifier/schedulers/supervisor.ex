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

    # Add kill charts-related schedulers if kill charts feature is enabled
    schedulers =
      if kill_charts_enabled?() do
        Logger.info("Kill charts feature enabled, adding killmail schedulers")

        # Add a brief delay to ensure the Repo is fully started
        Process.sleep(500)

        # Verify database connection is available
        db_ready? =
          try do
            case WandererNotifier.Repo.health_check() do
              {:ok, ping_time} ->
                Logger.info("Database connection verified - ping time: #{ping_time}ms")
                true

              {:error, reason} ->
                Logger.error("Database connection check failed: #{inspect(reason)}")

                Logger.warning(
                  "Starting without killmail schedulers due to database connection failure"
                )

                false
            end
          rescue
            e ->
              Logger.error("Database health check failed with exception: #{Exception.message(e)}")

              Logger.warning(
                "Starting without killmail schedulers due to database connection failure"
              )

              false
          end

        if db_ready? do
          schedulers ++
            [
              {WandererNotifier.Schedulers.KillmailAggregationScheduler, []},
              {WandererNotifier.Schedulers.KillmailRetentionScheduler, []},
              {WandererNotifier.Schedulers.KillmailChartScheduler, []}
            ]
        else
          schedulers
        end
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

  # Check if kill charts feature is enabled
  defp kill_charts_enabled? do
    WandererNotifier.Core.Config.kill_charts_enabled?()
  end
end
