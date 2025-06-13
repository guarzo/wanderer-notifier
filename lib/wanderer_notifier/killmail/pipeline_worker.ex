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
    defstruct redisq_pid: nil
  end

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    AppLogger.processor_info("Starting Pipeline Worker")
    state = %State{}

    # Start RedisQ client if enabled
    if Config.redisq_enabled?() do
      case start_redisq_client() do
        {:ok, pid} ->
          AppLogger.processor_info("RedisQ client started", pid: inspect(pid))
          {:ok, %{state | redisq_pid: pid}}

        {:error, reason} ->
          AppLogger.processor_error("Failed to start RedisQ client", reason: inspect(reason))
          # Don't crash the worker, just continue without RedisQ
          {:ok, state}
      end
    else
      AppLogger.processor_info("RedisQ disabled, starting worker without client")
      {:ok, state}
    end
  end

  @impl true
  def handle_info({:zkill_message, data}, state) do
    AppLogger.processor_debug("Received zkill message", data: inspect(data))

    # Process asynchronously using async_nolink to enable monitoring without linking
    task =
      Task.Supervisor.async_nolink(WandererNotifier.TaskSupervisor, fn ->
        case Processor.process_zkill_message(data, state) do
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
  def handle_info({:DOWN, _ref, :process, pid, reason}, %{redisq_pid: pid} = state) do
    AppLogger.processor_warn("RedisQ client died, attempting restart", reason: inspect(reason))

    # Attempt to restart the RedisQ client
    case start_redisq_client() do
      {:ok, new_pid} ->
        AppLogger.processor_info("RedisQ client restarted successfully", pid: inspect(new_pid))
        {:noreply, %{state | redisq_pid: new_pid}}

      {:error, restart_reason} ->
        AppLogger.processor_error("Failed to restart RedisQ client",
          error: inspect(restart_reason)
        )

        # Schedule a retry
        Process.send_after(self(), :retry_redisq_start, 30_000)
        {:noreply, %{state | redisq_pid: nil}}
    end
  end

  @impl true
  def handle_info(:retry_redisq_start, state) do
    if Config.redisq_enabled?() and is_nil(state.redisq_pid) do
      case start_redisq_client() do
        {:ok, pid} ->
          AppLogger.processor_info("RedisQ client started on retry", pid: inspect(pid))
          {:noreply, %{state | redisq_pid: pid}}

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
  def handle_info({ref, result}, state) when is_reference(ref) do
    # Task completed successfully
    AppLogger.processor_debug("Task completed", ref: inspect(ref), result: inspect(result))
    Process.demonitor(ref, [:flush])
    {:noreply, state}
  end

  @impl true
  def handle_info({:DOWN, ref, :process, _pid, reason}, state) when is_reference(ref) do
    # Task failed - log the failure but don't crash the worker
    case reason do
      :normal ->
        AppLogger.processor_debug("Task terminated normally", ref: inspect(ref))

      _ ->
        AppLogger.processor_warn("Task failed", ref: inspect(ref), reason: inspect(reason))
    end

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
