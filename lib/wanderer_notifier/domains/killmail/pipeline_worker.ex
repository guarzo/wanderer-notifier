defmodule WandererNotifier.Domains.Killmail.PipelineWorker do
  require Logger

  @moduledoc """
  Worker process that handles killmail processing pipeline.

  This GenServer:
  - Starts and manages the WebSocket client connection to external killmail service
  - Receives pre-enriched killmail messages from WebSocket client
  - Processes them asynchronously through the simplified killmail pipeline
  """

  use GenServer

  alias WandererNotifier.Domains.Killmail.{Pipeline, WebSocketClient}

  defmodule State do
    @moduledoc false
    defstruct websocket_pid: nil
  end

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    Logger.info("Starting Pipeline Worker - waiting for map initialization")
    state = %State{}

    # Don't start WebSocket immediately - wait for map initialization
    # If in test mode, start immediately
    if Application.get_env(:wanderer_notifier, :env) == :test do
      case start_websocket_client() do
        {:ok, pid} ->
          Logger.info("WebSocket client started (test mode)", pid: inspect(pid))
          {:ok, %{state | websocket_pid: pid}}

        {:error, reason} ->
          Logger.info("Failed to start WebSocket client, will retry",
            reason: inspect(reason)
          )

          Process.send_after(self(), :retry_websocket_start, 15_000)
          {:ok, state}
      end
    else
      # In normal mode, wait for map initialization signal
      Logger.info("Waiting for map initialization before starting WebSocket")
      {:ok, state}
    end
  end

  @impl true
  def handle_info({:websocket_killmail, killmail}, state) do
    log_killmail_received(killmail)
    WandererNotifier.Application.Services.Stats.track_killmail_received()

    _task = spawn_killmail_processing_task(killmail, state)

    {:noreply, state}
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, pid, reason}, %{websocket_pid: pid} = state) do
    Logger.info("WebSocket client died, attempting restart", reason: inspect(reason))

    # Attempt to restart the WebSocket client
    case start_websocket_client() do
      {:ok, new_pid} ->
        Logger.info("WebSocket client restarted successfully", pid: inspect(new_pid))
        {:noreply, %{state | websocket_pid: new_pid}}

      {:error, restart_reason} ->
        Logger.info("Failed to restart WebSocket client",
          error: inspect(restart_reason)
        )

        # Schedule a retry with longer delay
        Process.send_after(self(), :retry_websocket_start, 60_000)
        {:noreply, %{state | websocket_pid: nil}}
    end
  end

  @impl true
  def handle_info(:map_initialization_complete, state) do
    Logger.info("Map initialization complete signal received")

    if is_nil(state.websocket_pid) do
      case start_websocket_client() do
        {:ok, pid} ->
          Logger.info("WebSocket client started after map initialization",
            pid: inspect(pid)
          )

          {:noreply, %{state | websocket_pid: pid}}

        {:error, reason} ->
          Logger.info("Failed to start WebSocket client after map init, will retry",
            reason: inspect(reason)
          )

          Process.send_after(self(), :retry_websocket_start, 15_000)
          {:noreply, state}
      end
    else
      # WebSocket client already running
      {:noreply, state}
    end
  end

  @impl true
  def handle_info(:retry_websocket_start, state) do
    if is_nil(state.websocket_pid) do
      case start_websocket_client() do
        {:ok, pid} ->
          Logger.info("WebSocket client started on retry", pid: inspect(pid))
          {:noreply, %{state | websocket_pid: pid}}

        {:error, reason} ->
          Logger.info("Retry failed for WebSocket client", error: inspect(reason))
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
    Logger.info("Unhandled message in PipelineWorker", message: inspect(msg))
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

  defp log_killmail_received(killmail) do
    Logger.info("Received WebSocket killmail",
      killmail_id: killmail[:killmail_id],
      system_id: killmail[:system_id]
    )
  end

  defp spawn_killmail_processing_task(killmail, state) do
    Task.Supervisor.async_nolink(WandererNotifier.TaskSupervisor, fn ->
      process_killmail_task(killmail, state)
    end)
  end

  defp process_killmail_task(killmail, _state) do
    case Pipeline.process_killmail(killmail) do
      {:ok, :skipped} = success ->
        Logger.info("Killmail processing skipped")
        success

      {:ok, _killmail_id} = success ->
        Logger.info("Successfully processed killmail")
        success

      {:error, reason} ->
        log_killmail_processing_error(killmail, reason)
        {:error, reason}
    end
  end

  defp log_killmail_processing_error(killmail, reason) do
    Logger.info("Failed to process killmail",
      error: inspect(reason),
      killmail_id: Map.get(killmail, "killmail_id") || Map.get(killmail, :killmail_id),
      system_id: Map.get(killmail, "system_id") || Map.get(killmail, :system_id),
      data_keys: Map.keys(killmail)
    )
  end
end
