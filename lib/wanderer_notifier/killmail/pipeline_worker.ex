defmodule WandererNotifier.Killmail.PipelineWorker do
  @moduledoc """
  Worker process that handles killmail processing pipeline.

  This GenServer:
  - Receives zkill messages from the RedisQ client
  - Processes them asynchronously through the killmail pipeline
  """

  use GenServer

  alias WandererNotifier.Config
  alias WandererNotifier.Killmail.{Processor, RedisQClient}
  alias WandererNotifier.Logger.Logger, as: AppLogger

  defmodule State do
    @moduledoc false
    defstruct []
  end

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    AppLogger.processor_info("Starting Pipeline Worker")
    state = %State{}
    {:ok, state}
  end

  @impl true
  def handle_info({:zkill_message, data}, state) do
    AppLogger.processor_debug("Received zkill message", data: inspect(data))

    # Process asynchronously using Task.Supervisor to avoid blocking the GenServer
    Task.Supervisor.start_child(WandererNotifier.TaskSupervisor, fn ->
      case Processor.process_zkill_message(data, state) do
        {:ok, result} ->
          AppLogger.processor_debug("Successfully processed killmail", result: inspect(result))

        {:error, reason} ->
          AppLogger.processor_error("Failed to process killmail", error: inspect(reason))
      end
    end)

    {:noreply, state}
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, pid, reason}, %{redisq_pid: pid} = state) do
    AppLogger.processor_warn("RedisQ client died, attempting restart", reason: inspect(reason))

    # Attempt to restart the RedisQ client
    case start_redisq_client() do
      {:ok, new_pid} ->
        AppLogger.processor_info("RedisQ client restarted successfully", pid: inspect(new_pid))
        {:noreply, Map.put(state, :redisq_pid, new_pid)}

      {:error, restart_reason} ->
        AppLogger.processor_error("Failed to restart RedisQ client",
          error: inspect(restart_reason)
        )

        # Schedule a retry
        Process.send_after(self(), :retry_redisq_start, 30_000)
        {:noreply, Map.put(state, :redisq_pid, nil)}
    end
  end

  @impl true
  def handle_info(:retry_redisq_start, state) do
    if Config.redisq_enabled?() and is_nil(Map.get(state, :redisq_pid)) do
      case start_redisq_client() do
        {:ok, pid} ->
          AppLogger.processor_info("RedisQ client started on retry", pid: inspect(pid))
          {:noreply, Map.put(state, :redisq_pid, pid)}

        {:error, reason} ->
          AppLogger.processor_error("Retry failed to start RedisQ client", error: inspect(reason))
          # Schedule another retry
          Process.send_after(self(), :retry_redisq_start, 60_000)
          {:noreply, state}
      end
    else
      {:noreply, state}
    end
  end

  @impl true
  def handle_info({ref, _result}, state) when is_reference(ref) do
    # Ignore Task replies since we're using start_child (fire and forget)
    {:noreply, state}
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, _pid, :normal}, state) do
    # Ignore normal task termination
    {:noreply, state}
  end

  @impl true
  def handle_info(msg, state) do
    AppLogger.processor_warn("Received unexpected message", message: inspect(msg))
    {:noreply, state}
  end

  # Private functions

  defp start_redisq_client do
    opts = [
      parent: self(),
      queue_id: "wanderer_notifier",
      poll_interval: Config.redisq_poll_interval(),
      url: Config.redisq_url()
    ]

    case GenServer.start_link(RedisQClient, opts) do
      {:ok, pid} ->
        Process.monitor(pid)
        {:ok, pid}

      error ->
        error
    end
  end
end
