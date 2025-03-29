defmodule Schedulers.Supervisor do
  @moduledoc """
  Supervisor for all schedulers in the application.

  This module supervises the scheduler registry and all scheduler processes.
  """

  use Supervisor
  require Logger
  alias WandererNotifier.Core.Config
  alias WandererNotifier.Logger, as: AppLogger
  alias WandererNotifier.Logger.StartupTracker
  alias WandererNotifier.Resources.TrackedCharacter
  alias WandererNotifier.Schedulers
  alias WandererNotifier.Schedulers.Registry

  def start_link(opts \\ []) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    # Begin the scheduler phase in the startup tracker
    start_scheduler_phase()

    AppLogger.scheduler_info("Starting Scheduler Supervisor...")

    # Define the scheduler registry
    registry = {Registry, []}

    # Define core schedulers and build complete list
    core_schedulers = define_core_schedulers()
    schedulers = maybe_add_kill_chart_schedulers(core_schedulers)

    # Create children list with consolidated logging
    children = [registry | schedulers]

    # Single consolidated log message for all schedulers
    log_scheduler_summary(schedulers)

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
      {Schedulers.ActivityChartScheduler, []},
      {Schedulers.CharacterUpdateScheduler, []},
      {Schedulers.SystemUpdateScheduler, []}
    ]

    # Track core schedulers
    if Process.get(:startup_tracker) do
      StartupTracker.record_event(:scheduler_setup, %{
        core_schedulers: length(schedulers)
      })
    end

    schedulers
  end

  # Add kill charts schedulers if feature is enabled and database is available
  defp maybe_add_kill_chart_schedulers(core_schedulers) do
    if Config.kill_charts_enabled?() && database_ready?() do
      kill_chart_schedulers = [
        {Schedulers.KillmailRetentionScheduler, []},
        {Schedulers.KillmailAggregationScheduler, []}
      ]

      # Track kill chart schedulers
      if Process.get(:startup_tracker) do
        StartupTracker.record_event(:scheduler_setup, %{
          kill_chart_schedulers: length(kill_chart_schedulers)
        })
      end

      core_schedulers ++ kill_chart_schedulers
    else
      if Config.kill_charts_enabled?() do
        AppLogger.scheduler_warn(
          "Kill charts enabled but database not ready, skipping kill chart schedulers"
        )
      end

      core_schedulers
    end
  end

  # Check if database is ready
  @doc """
  Checks if the database connection is ready.
  Returns true if the database is not required or if the connection is established.
  """
  def database_ready? do
    if TrackedCharacter.database_enabled?() do
      # Add a brief delay to ensure the Repo is fully started
      Process.sleep(500)

      case WandererNotifier.Repo.health_check() do
        {:ok, ping_time} ->
          record_database_status("verified", ping_time)
          true

        {:error, reason} ->
          record_database_error(
            "Database connection check failed during scheduler setup",
            reason
          )

          false
      end
    else
      true
    end
  end

  # Record database status
  defp record_database_status(status, ping_time) do
    if Process.get(:startup_tracker) do
      StartupTracker.record_event(:database_status, %{
        status: status,
        ping_time: ping_time
      })
    end
  end

  # Record database error
  defp record_database_error(message, reason) do
    if Process.get(:startup_tracker) do
      StartupTracker.record_error(
        message,
        %{reason: inspect(reason)}
      )
    else
      AppLogger.scheduler_error("Database connection check failed: #{inspect(reason)}")
    end
  end

  # Log a summary of all schedulers being started
  defp log_scheduler_summary(schedulers) do
    if Process.get(:startup_tracker) do
      StartupTracker.log_state_change(
        :scheduler_summary,
        "#{length(schedulers)} schedulers initialized"
      )
    else
      AppLogger.scheduler_info("Starting #{length(schedulers)} schedulers")
    end
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
