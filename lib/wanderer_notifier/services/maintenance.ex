defmodule WandererNotifier.Services.Maintenance do
  @moduledoc """
  Handles periodic maintenance tasks for the application.
  Includes system and character updates and health checks.

  Note: This module is deprecated and will be removed in a future version.
  Please use WandererNotifier.Core.Maintenance.Service instead.
  """
  use GenServer
  require Logger
  alias WandererNotifier.Core.Logger, as: AppLogger
  alias WandererNotifier.Core.Maintenance.Service, as: MaintenanceService

  @deprecated "Use WandererNotifier.Core.Maintenance.Service instead"
  def start_link(opts) do
    AppLogger.maintenance_warn(
      "WandererNotifier.Services.Maintenance is deprecated, please use WandererNotifier.Core.Maintenance.Service instead"
    )

    MaintenanceService.start_link(opts)
  end

  @impl true
  def init(opts) do
    AppLogger.maintenance_warn(
      "WandererNotifier.Services.Maintenance is deprecated, please use WandererNotifier.Core.Maintenance.Service instead"
    )

    MaintenanceService.init(opts)
  end

  @impl true
  def handle_info(msg, state) do
    # Simply delegate to the new module
    MaintenanceService.handle_info(msg, state)
  end
end
