defmodule WandererNotifier.Domains.Killmail.Supervisor do
  @moduledoc """
  Supervisor for the killmail processing pipeline.

  This supervisor manages:
  - The RedisQ client that fetches killmails from zkillboard
  - The pipeline processor that handles incoming killmail messages
  """

  use Supervisor
  require Logger

  def start_link(init_arg \\ []) do
    opts = [name: __MODULE__]
    Supervisor.start_link(__MODULE__, init_arg, opts)
  end

  @impl true
  def init(_init_arg) do
    Logger.info(
      "Starting Killmail Supervisor with WebSocketClient, PipelineWorker and FallbackHandler",
      category: :processor
    )

    children = [
      # Start the pipeline worker that will process messages
      {WandererNotifier.Domains.Killmail.PipelineWorker, []},
      # Start the fallback handler for HTTP API access
      {WandererNotifier.Domains.Killmail.FallbackHandler, []}
      # WebSocket client will be started asynchronously after application startup
    ]

    # Start WebSocket client asynchronously to avoid blocking startup
    spawn(fn ->
      # Wait for application to fully start
      Process.sleep(2000)
      start_websocket_client()
    end)

    Supervisor.init(children, strategy: :one_for_one)
  end

  defp start_websocket_client do
    Logger.info("Starting WebSocket client asynchronously")

    case WandererNotifier.Domains.Killmail.WebSocketClient.start_link() do
      {:ok, pid} ->
        Logger.info("WebSocket client started successfully", pid: inspect(pid))

      {:error, reason} ->
        Logger.warning("WebSocket client failed to start, will be handled by fallback",
          reason: inspect(reason)
        )
    end
  end
end
