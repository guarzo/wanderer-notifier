defmodule WandererNotifier.Killmail.PipelineWorker do
  @moduledoc """
  Worker process that manages the killmail processing pipeline.

  This GenServer:
  - Acts as the parent process for the RedisQ client
  - Receives zkill messages from the RedisQ client
  - Processes them through the killmail pipeline
  """

  use GenServer

  alias WandererNotifier.Config
  alias WandererNotifier.Killmail.{Processor, RedisQClient}
  alias WandererNotifier.Logger.Logger, as: AppLogger

  defmodule State do
    @moduledoc false
    defstruct [:redisq_pid, :stats]
  end

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    AppLogger.processor_info("Starting Pipeline Worker")

    # Start the RedisQ client if enabled
    state = %State{stats: %{processed: 0, errors: 0}}

    if Config.redisq_enabled?() do
      case start_redisq_client() do
        {:ok, pid} ->
          AppLogger.processor_info("RedisQ client started successfully", pid: inspect(pid))
          {:ok, %{state | redisq_pid: pid}}

        {:error, reason} ->
          AppLogger.processor_error("Failed to start RedisQ client", error: inspect(reason))
          # Continue without RedisQ - it can be started later
          {:ok, state}
      end
    else
      AppLogger.processor_info("RedisQ disabled, skipping client startup")
      {:ok, state}
    end
  end

  @impl true
  def handle_info({:zkill_message, data}, state) do
    AppLogger.processor_debug("Received zkill message", data: inspect(data))

    # Process through the pipeline
    case Processor.process_zkill_message(data, state) do
      {:ok, result} ->
        AppLogger.processor_debug("Successfully processed killmail", result: inspect(result))
        {:noreply, update_stats(state, :processed)}

      {:error, reason} ->
        AppLogger.processor_error("Failed to process killmail", error: inspect(reason))
        {:noreply, update_stats(state, :errors)}
    end
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

  defp update_stats(state, type) do
    stats = Map.update!(state.stats, type, &(&1 + 1))
    %{state | stats: stats}
  end
end
