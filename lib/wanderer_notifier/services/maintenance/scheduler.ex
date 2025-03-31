defmodule WandererNotifier.Services.Maintenance.Scheduler do
  @moduledoc """
  Schedules and executes maintenance tasks.
  Handles periodic updates for systems and characters.

  Note: This module is deprecated and will be removed in a future version.
  Please use WandererNotifier.Core.Maintenance.Scheduler instead.
  """
  alias WandererNotifier.Core.Logger, as: AppLogger
  alias WandererNotifier.Core.Maintenance.Scheduler, as: MaintenanceScheduler

  @doc """
  Performs periodic maintenance tasks.
  - Updates tracked systems
  - Updates tracked characters
  - Performs health checks
  """
  @deprecated "Use WandererNotifier.Core.Maintenance.Scheduler.tick/1 instead"
  def tick(state) do
    AppLogger.maintenance_warn(
      "WandererNotifier.Services.Maintenance.Scheduler.tick/1 is deprecated, please use WandererNotifier.Core.Maintenance.Scheduler.tick/1 instead"
    )

    MaintenanceScheduler.tick(state)
  end

  @doc """
  Performs initial checks when the service starts.
  Forces a full update of all systems and characters.
  """
  @deprecated "Use WandererNotifier.Core.Maintenance.Scheduler.do_initial_checks/1 instead"
  def do_initial_checks(state) do
    AppLogger.maintenance_warn(
      "WandererNotifier.Services.Maintenance.Scheduler.do_initial_checks/1 is deprecated, please use WandererNotifier.Core.Maintenance.Scheduler.do_initial_checks/1 instead"
    )

    MaintenanceScheduler.do_initial_checks(state)
  end

  @doc """
  Sends a status report if not duplicated.
  """
  @deprecated "Use WandererNotifier.Core.Maintenance.Scheduler.send_status_report/0 instead"
  def send_status_report do
    AppLogger.maintenance_warn(
      "WandererNotifier.Services.Maintenance.Scheduler.send_status_report/0 is deprecated, please use WandererNotifier.Core.Maintenance.Scheduler.send_status_report/0 instead"
    )

    MaintenanceScheduler.send_status_report()
  end
end
