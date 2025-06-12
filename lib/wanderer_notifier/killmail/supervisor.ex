defmodule WandererNotifier.Killmail.Supervisor do
  @moduledoc """
  Supervisor for the killmail processing pipeline.

  This supervisor manages:
  - The RedisQ client that fetches killmails from zkillboard
  - The pipeline processor that handles incoming killmail messages
  """

  use Supervisor

  alias WandererNotifier.Logger.Logger, as: AppLogger

  def start_link(init_arg \\ []) do
    opts = [name: __MODULE__]
    Supervisor.start_link(__MODULE__, init_arg, opts)
  end

  @impl true
  def init(_init_arg) do
    AppLogger.processor_info("Starting Killmail Supervisor")

    children = [
      # Start the pipeline worker that will process messages
      {WandererNotifier.Killmail.PipelineWorker, []}
      # RedisQ client will be started by the PipelineWorker which acts as its parent
    ]

    Supervisor.init(children, strategy: :one_for_all)
  end
end
