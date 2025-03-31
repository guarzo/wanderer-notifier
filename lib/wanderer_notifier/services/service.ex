defmodule WandererNotifier.Services.Service do
  @moduledoc """
  The main WandererNotifier service (GenServer).
  Coordinates periodic maintenance and kill processing.

  Note: This module is deprecated and will be removed in a future version.
  Please use WandererNotifier.Core.Application.Service instead.
  """

  require Logger
  use GenServer
  alias WandererNotifier.Core.Application.Service, as: ApplicationService
  alias WandererNotifier.Core.Logger, as: AppLogger

  @deprecated "Use WandererNotifier.Core.Application.Service instead"
  def start_link(opts \\ []) do
    AppLogger.startup_warn(
      "WandererNotifier.Services.Service is deprecated, please use WandererNotifier.Core.Application.Service instead"
    )

    ApplicationService.start_link(opts)
  end

  @deprecated "Use WandererNotifier.Core.Application.Service.stop/0 instead"
  def stop do
    ApplicationService.stop()
  end

  @impl true
  def init(opts) do
    AppLogger.startup_warn(
      "WandererNotifier.Services.Service is deprecated, please use WandererNotifier.Core.Application.Service instead"
    )

    ApplicationService.init(opts)
  end

  @impl true
  def handle_cast(message, state) do
    # Delegate to the ApplicationService module
    ApplicationService.handle_cast(message, state)
  end

  @impl true
  def handle_info(message, state) do
    # Delegate to the ApplicationService module
    ApplicationService.handle_info(message, state)
  end

  @impl true
  def terminate(reason, state) do
    # Delegate to the ApplicationService module
    ApplicationService.terminate(reason, state)
  end

  @deprecated "Use WandererNotifier.Core.Application.Service.mark_as_processed/1 instead"
  def mark_as_processed(kill_id) do
    AppLogger.processor_warn(
      "WandererNotifier.Services.Service.mark_as_processed/1 is deprecated, please use WandererNotifier.Core.Application.Service.mark_as_processed/1 instead"
    )

    ApplicationService.mark_as_processed(kill_id)
  end

  @deprecated "Use WandererNotifier.Core.Application.Service.debug_tracked_systems/0 instead"
  def debug_tracked_systems do
    AppLogger.processor_warn(
      "WandererNotifier.Services.Service.debug_tracked_systems/0 is deprecated, please use WandererNotifier.Core.Application.Service.debug_tracked_systems/0 instead"
    )

    ApplicationService.debug_tracked_systems()
  end

  @deprecated "Use WandererNotifier.Core.Application.Service.get_recent_kills/0 instead"
  def get_recent_kills do
    AppLogger.processor_warn(
      "WandererNotifier.Services.Service.get_recent_kills/0 is deprecated, please use WandererNotifier.Core.Application.Service.get_recent_kills/0 instead"
    )

    ApplicationService.get_recent_kills()
  end

  @deprecated "Use WandererNotifier.Core.Application.Service.send_test_kill_notification/0 instead"
  def send_test_kill_notification do
    AppLogger.processor_warn(
      "WandererNotifier.Services.Service.send_test_kill_notification/0 is deprecated, please use WandererNotifier.Core.Application.Service.send_test_kill_notification/0 instead"
    )

    ApplicationService.send_test_kill_notification()
  end

  @deprecated "Use WandererNotifier.Core.Application.Service.start_websocket/0 instead"
  def start_websocket do
    AppLogger.processor_warn(
      "WandererNotifier.Services.Service.start_websocket/0 is deprecated, please use WandererNotifier.Core.Application.Service.start_websocket/0 instead"
    )

    ApplicationService.start_websocket()
  end
end
