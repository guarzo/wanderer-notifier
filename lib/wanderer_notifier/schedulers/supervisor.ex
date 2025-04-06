defmodule WandererNotifier.Schedulers.Supervisor do
  @moduledoc """
  Supervisor for scheduler modules.
  Manages the lifecycle of all scheduler processes.
  """

  use Supervisor
  alias WandererNotifier.Data.Repo
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
    schedulers = maybe_add_kill_chart_schedulers(core_schedulers)

    # Create children list with consolidated logging
    children = [registry | schedulers]

    # Single consolidated log message for all schedulers
    AppLogger.startup_info("⏰ Scheduler system ready (#{length(schedulers)} schedulers)")

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

  # Add kill charts schedulers if feature is enabled and database is available
  defp maybe_add_kill_chart_schedulers(core_schedulers) do
    persistence_config = Application.get_env(:wanderer_notifier, :persistence, [])
    kill_charts_enabled = Keyword.get(persistence_config, :enabled)

    if kill_charts_enabled do
      add_kill_chart_schedulers_if_db_ready(core_schedulers)
    else
      AppLogger.scheduler_info("Kill charts feature disabled, skipping kill chart schedulers")
      core_schedulers
    end
  end

  # Add kill chart schedulers if database is ready
  defp add_kill_chart_schedulers_if_db_ready(core_schedulers) do
    if database_ready?() do
      kill_chart_schedulers = create_kill_chart_schedulers()
      track_kill_chart_schedulers(kill_chart_schedulers)
      core_schedulers ++ kill_chart_schedulers
    else
      AppLogger.scheduler_warn(
        "Kill charts enabled but database not ready, skipping kill chart schedulers"
      )

      core_schedulers
    end
  end

  # Create the list of kill chart schedulers
  defp create_kill_chart_schedulers do
    [
      {Schedulers.KillmailRetentionScheduler, []},
      {Schedulers.KillmailAggregationScheduler, []},
      {Schedulers.KillValidationChartScheduler, []},
      {Schedulers.WeeklyKillChartScheduler, []},
      {Schedulers.WeeklyKillDataScheduler, []},
      {Schedulers.WeeklyKillHighlightsScheduler, []}
    ]
  end

  # Track kill chart schedulers in startup tracker
  defp track_kill_chart_schedulers(kill_chart_schedulers) do
    if Process.get(:startup_tracker) do
      StartupTracker.record_event(:scheduler_setup, %{
        kill_chart_schedulers: length(kill_chart_schedulers)
      })
    end
  end

  # Check if database is ready
  @doc """
  Checks if the database connection is ready.
  Returns true if the database is not required or if the connection is established.
  """
  def database_ready? do
    persistence_config = Application.get_env(:wanderer_notifier, :persistence, [])
    kill_charts_enabled = Keyword.get(persistence_config, :enabled)
    map_charts_enabled = Application.get_env(:wanderer_notifier, :wanderer_feature_map_charts)

    if kill_charts_enabled == false && map_charts_enabled == false do
      AppLogger.scheduler_info("Database features disabled, skipping database check")
      true
    else
      # Add a brief delay to ensure the Repo is fully started
      Process.sleep(500)

      case Repo.health_check() do
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
