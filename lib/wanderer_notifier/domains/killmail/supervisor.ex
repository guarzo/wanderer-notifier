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

  @initial_retry_delay 5_000
  @max_retry_delay 60_000

  @doc """
  Starts the Killmail Supervisor.
  """
  def start_link(init_arg \\ []) do
    GenServer.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @doc """
  Returns the PID of the internal supervisor.

  ## Returns
  - `{:ok, pid}` if the supervisor is running
  - `{:error, :not_started}` if the supervisor is not running
  """
  @spec supervisor_pid() :: {:ok, pid()} | {:error, :not_started}
  def supervisor_pid do
    case Process.whereis(__MODULE__) do
      nil ->
        {:error, :not_started}

      _pid ->
        try do
          GenServer.call(__MODULE__, :get_supervisor_pid)
        catch
          :exit, _ -> {:error, :not_started}
        end
    end
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
    case start_websocket_client() do
      {:ok, _pid} ->
        {:noreply, state}

      {:error, reason} ->
        Logger.warning("WebSocket client failed to start, scheduling retry",
          reason: inspect(reason),
          retry_in_ms: @initial_retry_delay,
          category: :processor
        )

        schedule_websocket_retry(state, 0)
    end
  end

  @impl true
  def handle_info(:retry_websocket, state) do
    attempts = Map.get(state, :ws_retry_attempts, 0)

    case start_websocket_client() do
      {:ok, _pid} ->
        Logger.info("WebSocket client started after #{attempts + 1} retry attempt(s)",
          category: :processor
        )

        {:noreply, Map.delete(state, :ws_retry_attempts)}

      {:error, reason} ->
        delay = calculate_retry_delay(attempts + 1)

        Logger.warning("WebSocket client retry failed, will retry again",
          reason: inspect(reason),
          attempt: attempts + 1,
          retry_in_ms: delay,
          category: :processor
        )

        schedule_websocket_retry(state, attempts + 1)
    end
  end

  @impl true
  def handle_call(:get_supervisor_pid, _from, %{supervisor_pid: pid} = state) when is_pid(pid) do
    {:reply, {:ok, pid}, state}
  end

  def handle_call(:get_supervisor_pid, _from, state) do
    {:reply, {:error, :not_started}, state}
  end

  # ──────────────────────────────────────────────────────────────────────────────
  # Private Functions
  # ──────────────────────────────────────────────────────────────────────────────

  defp start_websocket_client do
    Logger.info("Starting WebSocket client", category: :processor)

    case WandererNotifier.Domains.Killmail.WebSocketClient.start_link() do
      {:ok, pid} ->
        Logger.info("WebSocket client started successfully", pid: inspect(pid))
        {:ok, pid}

      {:error, reason} ->
        Logger.warning("WebSocket client failed to start",
          reason: inspect(reason),
          category: :processor
        )

        {:error, reason}
    end
  end

  defp schedule_websocket_retry(state, attempts) do
    delay = calculate_retry_delay(attempts)
    Process.send_after(self(), :retry_websocket, delay)
    {:noreply, Map.put(state, :ws_retry_attempts, attempts)}
  end

  defp calculate_retry_delay(attempts) do
    delay = @initial_retry_delay * Integer.pow(2, min(attempts, 10))
    min(delay, @max_retry_delay)
  end
end
