defmodule WandererNotifier.Domains.Killmail.Supervisor do
  @moduledoc """
  Supervisor for the killmail processing pipeline.

  This supervisor manages:
  - The WebSocket client that receives killmails in real-time
  - The pipeline processor that handles incoming killmail messages

  Uses a GenServer-based supervisor pattern to enable handle_continue for
  proper startup sequencing of the WebSocket client.
  """

  use GenServer
  require Logger

  @doc """
  Starts the Killmail Supervisor.
  """
  def start_link(init_arg \\ []) do
    GenServer.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @doc """
  Returns the PID of the internal supervisor.
  """
  def supervisor_pid do
    GenServer.call(__MODULE__, :get_supervisor_pid)
  end

  # ──────────────────────────────────────────────────────────────────────────────
  # GenServer Callbacks
  # ──────────────────────────────────────────────────────────────────────────────

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
    ]

    # Start the internal supervisor synchronously
    case Supervisor.start_link(children,
           strategy: :one_for_one,
           name: __MODULE__.InternalSupervisor
         ) do
      {:ok, supervisor_pid} ->
        # Use handle_continue to start WebSocket client after supervisor is ready
        {:ok, %{supervisor_pid: supervisor_pid}, {:continue, :start_websocket}}

      {:error, reason} ->
        {:stop, reason}
    end
  end

  @impl true
  def handle_continue(:start_websocket, state) do
    # Start WebSocket client using TaskSupervisor for proper crash propagation
    Task.Supervisor.start_child(WandererNotifier.TaskSupervisor, fn ->
      start_websocket_client()
    end)

    {:noreply, state}
  end

  @impl true
  def handle_call(:get_supervisor_pid, _from, %{supervisor_pid: pid} = state) do
    {:reply, pid, state}
  end

  # ──────────────────────────────────────────────────────────────────────────────
  # Private Functions
  # ──────────────────────────────────────────────────────────────────────────────

  defp start_websocket_client do
    Logger.info("Starting WebSocket client via TaskSupervisor", category: :processor)

    case WandererNotifier.Domains.Killmail.WebSocketClient.start_link() do
      {:ok, pid} ->
        Logger.info("WebSocket client started successfully", pid: inspect(pid))
        {:ok, pid}

      {:error, reason} ->
        Logger.warning("WebSocket client failed to start, will be handled by fallback",
          reason: inspect(reason)
        )

        {:error, reason}
    end
  end
end
