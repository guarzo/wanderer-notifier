defmodule WandererNotifier.Application.Supervisors.KillmailSupervisor do
  @moduledoc """
  Reorganized supervisor for killmail processing.
  Manages all killmail-related processes including clients and workers.
  """
  use Supervisor

  alias WandererNotifier.Shared.Logger.Logger, as: AppLogger

  def start_link(init_arg) do
    Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    AppLogger.startup_info("Starting Killmail Supervisor")

    children = [
      # Killmail-specific task supervisor for processing tasks
      {Task.Supervisor, name: WandererNotifier.KillmailTaskSupervisor},

      # Pipeline worker for processing killmails with WebSocket client
      {WandererNotifier.Domains.Killmail.PipelineWorker, []}
    ]

    # Use one_for_all strategy - if any component fails, restart all
    # This ensures the pipeline stays consistent
    Supervisor.init(children, strategy: :one_for_all)
  end
end
