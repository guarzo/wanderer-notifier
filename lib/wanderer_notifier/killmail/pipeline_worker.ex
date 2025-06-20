defmodule WandererNotifier.Killmail.PipelineWorker do
  @moduledoc """
  Worker process that handles killmail processing pipeline.

  This GenServer:
  - Starts and manages the WebSocket client connection to external killmail service
  - Receives pre-enriched killmail messages from WebSocket client
  - Processes them asynchronously through the simplified killmail pipeline
  """

  use GenServer

  alias WandererNotifier.Killmail.{Processor, WebSocketClient}
  alias WandererNotifier.Logger.Logger, as: AppLogger

  defmodule State do
    @moduledoc false
    defstruct websocket_pid: nil
  end

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    AppLogger.processor_info("Starting Pipeline Worker with WebSocket client")
    state = %State{}

    # Check if WebSocket is enabled
    websocket_enabled = Application.get_env(:wanderer_notifier, :websocket_enabled, true)

    if websocket_enabled do
      case start_websocket_client() do
        {:ok, pid} ->
          AppLogger.processor_info("WebSocket client started", pid: inspect(pid))
          {:ok, %{state | websocket_pid: pid}}

        {:error, reason} ->
          AppLogger.processor_warn("Failed to start WebSocket client, will retry",
            reason: inspect(reason)
          )

          # Don't crash the worker, but schedule a retry
          Process.send_after(self(), :retry_websocket_start, 15_000)
          {:ok, state}
      end
    else
      AppLogger.processor_info("WebSocket client disabled by configuration")
      {:ok, state}
    end
  end

  @impl true
  def handle_info({:websocket_killmail, killmail}, state) do
    AppLogger.processor_debug("Received WebSocket killmail",
      killmail_id: killmail[:killmail_id],
      system_id: killmail[:system_id]
    )

    # Process asynchronously using async_nolink to enable monitoring without linking
    task =
      Task.Supervisor.async_nolink(WandererNotifier.TaskSupervisor, fn ->
        case Processor.process_websocket_killmail(killmail, state) do
          {:ok, result} ->
            AppLogger.processor_debug("Successfully processed killmail", result: inspect(result))
            result

          {:error, reason} ->
            AppLogger.processor_error("Failed to process killmail", error: inspect(reason))
            {:error, reason}
        end
      end)

    # Store task reference for monitoring (optional - we could track processing tasks)
    _task_ref = task.ref

    {:noreply, state}
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, pid, reason}, %{websocket_pid: pid} = state) do
    AppLogger.processor_warn("WebSocket client died, attempting restart", reason: inspect(reason))

    # Attempt to restart the WebSocket client
    case start_websocket_client() do
      {:ok, new_pid} ->
        AppLogger.processor_info("WebSocket client restarted successfully", pid: inspect(new_pid))
        {:noreply, %{state | websocket_pid: new_pid}}

      {:error, restart_reason} ->
        AppLogger.processor_error("Failed to restart WebSocket client",
          error: inspect(restart_reason)
        )

        # Schedule a retry with longer delay
        Process.send_after(self(), :retry_websocket_start, 60_000)
        {:noreply, %{state | websocket_pid: nil}}
    end
  end

  @impl true
  def handle_info(:retry_websocket_start, state) do
    if is_nil(state.websocket_pid) do
      case start_websocket_client() do
        {:ok, pid} ->
          AppLogger.processor_info("WebSocket client started on retry", pid: inspect(pid))
          {:noreply, %{state | websocket_pid: pid}}

        {:error, reason} ->
          AppLogger.processor_error("Retry failed for WebSocket client", error: inspect(reason))
          # Schedule another retry with longer delay
          Process.send_after(self(), :retry_websocket_start, 60_000)
          {:noreply, state}
      end
    else
      # WebSocket client already running
      {:noreply, state}
    end
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, _pid, _reason}, state) do
    # Handle other DOWN messages (like from tasks)
    {:noreply, state}
  end

  @impl true
  def handle_info(msg, state) do
    AppLogger.processor_debug("Unhandled message in PipelineWorker", message: inspect(msg))
    {:noreply, state}
  end

  # Private helper functions

  defp start_websocket_client do
    case WebSocketClient.start_link(pipeline_worker: self()) do
      {:ok, pid} ->
        # Monitor the WebSocket client process
        Process.monitor(pid)
        {:ok, pid}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
