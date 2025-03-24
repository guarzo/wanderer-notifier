defmodule WandererNotifier.Schedulers.Supervisor do
  @moduledoc """
  Supervisor for all schedulers in the application.

  This module supervises the scheduler registry and all scheduler processes.
  """

  use Supervisor
  require Logger
  alias WandererNotifier.Logger, as: AppLogger

  def start_link(opts \\ []) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    # Begin the scheduler phase in the startup tracker
    start_scheduler_phase()

    AppLogger.scheduler_info("Starting Scheduler Supervisor...")

    # Define the scheduler registry
    registry = {WandererNotifier.Schedulers.Registry, []}

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
      WandererNotifier.Logger.StartupTracker.begin_phase(:schedulers, "Initializing schedulers")
    end
  end

  # Define the core schedulers
  defp define_core_schedulers do
    schedulers = [
      {WandererNotifier.Schedulers.ActivityChartScheduler, []},
      {WandererNotifier.Schedulers.CharacterUpdateScheduler, []},
      {WandererNotifier.Schedulers.SystemUpdateScheduler, []}
    ]

    # Track core schedulers
    if Process.get(:startup_tracker) do
      WandererNotifier.Logger.StartupTracker.record_event(:scheduler_setup, %{
        core_schedulers: length(schedulers)
      })
    end

    schedulers
  end

  # Add kill charts schedulers if feature is enabled
  defp maybe_add_kill_chart_schedulers(core_schedulers) do
    if kill_charts_enabled?() do
      record_feature_status("kill_charts", true)

      if database_ready?() do
        killmail_schedulers = define_killmail_schedulers()
        core_schedulers ++ killmail_schedulers
      else
        record_skipped_schedulers()
        core_schedulers
      end
    else
      record_feature_status("kill_charts", false)
      core_schedulers
    end
  end

  # Define the killmail schedulers
  defp define_killmail_schedulers do
    killmail_schedulers = [
      {WandererNotifier.Schedulers.KillmailAggregationScheduler, []},
      {WandererNotifier.Schedulers.KillmailRetentionScheduler, []},
      {WandererNotifier.Schedulers.KillmailChartScheduler, []}
    ]

    # Record killmail schedulers in tracker
    if Process.get(:startup_tracker) do
      WandererNotifier.Logger.StartupTracker.record_event(:scheduler_setup, %{
        killmail_schedulers: length(killmail_schedulers)
      })
    end

    killmail_schedulers
  end

  # Record if a feature is enabled or disabled
  defp record_feature_status(feature, enabled) do
    if Process.get(:startup_tracker) do
      WandererNotifier.Logger.StartupTracker.record_event(:feature_status, %{
        feature: feature,
        enabled: enabled
      })
    end
  end

  # Record that schedulers were skipped
  defp record_skipped_schedulers do
    if Process.get(:startup_tracker) do
      WandererNotifier.Logger.StartupTracker.record_event(:scheduler_setup, %{
        skipped_killmail_schedulers: 3,
        reason: "database_not_ready"
      })
    end
  end

  # Check if the database is ready
  defp database_ready? do
    # Add a brief delay to ensure the Repo is fully started
    Process.sleep(500)

    try do
      case WandererNotifier.Repo.health_check() do
        {:ok, ping_time} ->
          record_database_status("verified", ping_time)
          true

        {:error, reason} ->
          record_database_error("Database connection check failed during scheduler setup", reason)

          Logger.warning(
            "Starting without killmail schedulers due to database connection failure"
          )

          false
      end
    rescue
      e ->
        record_database_exception("Database health check exception during scheduler setup", e)
        Logger.warning("Starting without killmail schedulers due to database connection failure")
        false
    end
  end

  # Record database status
  defp record_database_status(status, ping_time) do
    if Process.get(:startup_tracker) do
      WandererNotifier.Logger.StartupTracker.record_event(:database_status, %{
        status: status,
        ping_time: ping_time
      })
    end
  end

  # Record database error
  defp record_database_error(message, reason) do
    if Process.get(:startup_tracker) do
      WandererNotifier.Logger.StartupTracker.record_error(
        message,
        %{reason: inspect(reason)}
      )
    else
      AppLogger.scheduler_error("Database connection check failed: #{inspect(reason)}")
    end
  end

  # Record database exception
  defp record_database_exception(message, exception) do
    if Process.get(:startup_tracker) do
      WandererNotifier.Logger.StartupTracker.record_error(
        message,
        %{error: Exception.message(exception)}
      )
    else
      AppLogger.scheduler_error(
        "Database health check failed with exception: #{Exception.message(exception)}"
      )
    end
  end

  # Log a summary of all schedulers being started
  defp log_scheduler_summary(schedulers) do
    if Process.get(:startup_tracker) do
      WandererNotifier.Logger.StartupTracker.log_state_change(
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
        WandererNotifier.Schedulers.Registry.register(scheduler_module)
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

  # Check if kill charts feature is enabled
  defp kill_charts_enabled? do
    WandererNotifier.Core.Config.kill_charts_enabled?()
  end
end
