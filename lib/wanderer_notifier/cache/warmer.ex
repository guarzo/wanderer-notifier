defmodule WandererNotifier.Cache.Warmer do
  @moduledoc """
  Cache warmer GenServer for background cache warming and maintenance.

  This module provides background cache warming functionality to ensure
  critical data is preloaded into cache before it's needed, reducing
  cache misses and improving application performance.

  ## Features

  - Background cache warming for critical data
  - Configurable warming strategies
  - Scheduled cache refresh for high-TTL items
  - Priority-based warming queue
  - Warming progress tracking and reporting
  - Integration with performance monitoring

  ## Configuration

  The warmer can be configured with various strategies and intervals:

  ```elixir
  config :wanderer_notifier, WandererNotifier.Cache.Warmer,
    warming_interval: 300_000,    # 5 minutes
    startup_warming: true,        # Enable startup warming
    max_concurrent_jobs: 10,      # Maximum concurrent warming jobs
    warming_timeout: 30_000       # 30 seconds timeout per job
  ```

  ## Usage

  ```elixir
  # Start cache warming
  WandererNotifier.Cache.Warmer.start_warming()

  # Warm specific data
  WandererNotifier.Cache.Warmer.warm_character(123456)
  WandererNotifier.Cache.Warmer.warm_system(30000142)

  # Get warming status
  status = WandererNotifier.Cache.Warmer.get_status()
  ```
  """

  use GenServer
  require Logger

  alias WandererNotifier.Cache.Facade
  alias WandererNotifier.Cache.Metrics
  alias WandererNotifier.Cache.WarmingStrategies

  @type warming_priority :: :low | :medium | :high | :critical
  @type warming_job :: %{
          id: String.t(),
          type: atom(),
          data: term(),
          priority: warming_priority(),
          created_at: integer(),
          started_at: integer() | nil,
          completed_at: integer() | nil,
          status: :pending | :running | :completed | :failed,
          error: term() | nil
        }

  # Default configuration
  @default_config %{
    # 5 minutes
    warming_interval: 300_000,
    # Disable startup warming to improve startup performance
    startup_warming: false,
    # Maximum concurrent warming jobs
    max_concurrent_jobs: 10,
    # 30 seconds timeout per job
    warming_timeout: 30_000,
    # Retry failed jobs
    retry_failed_jobs: true,
    # 1 minute delay before retry
    retry_delay: 60_000,
    # Maximum retry attempts
    max_retries: 3,
    # Maximum queue size
    queue_size_limit: 1000
  }

  @doc """
  Starts the cache warmer GenServer.

  ## Options
  - All options from @default_config can be overridden
  - `:name` - Name for the GenServer (default: __MODULE__)
  """
  def start_link(opts \\ []) do
    {name, opts} = Keyword.pop(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Starts cache warming process.

  ## Returns
  :ok
  """
  @spec start_warming() :: :ok
  def start_warming do
    GenServer.call(__MODULE__, :start_warming)
  end

  @doc """
  Stops cache warming process.

  ## Returns
  :ok
  """
  @spec stop_warming() :: :ok
  def stop_warming do
    GenServer.call(__MODULE__, :stop_warming)
  end

  @doc """
  Warms character data for a specific character ID.

  ## Parameters
  - character_id: EVE character ID
  - priority: Warming priority (default: :medium)

  ## Returns
  {:ok, job_id} | {:error, reason}
  """
  @spec warm_character(integer() | String.t(), warming_priority()) ::
          {:ok, String.t()} | {:error, term()}
  def warm_character(character_id, priority \\ :medium) do
    GenServer.call(__MODULE__, {:queue_job, :character, character_id, priority})
  end

  @doc """
  Warms corporation data for a specific corporation ID.

  ## Parameters
  - corporation_id: EVE corporation ID
  - priority: Warming priority (default: :medium)

  ## Returns
  {:ok, job_id} | {:error, reason}
  """
  @spec warm_corporation(integer() | String.t(), warming_priority()) ::
          {:ok, String.t()} | {:error, term()}
  def warm_corporation(corporation_id, priority \\ :medium) do
    GenServer.call(__MODULE__, {:queue_job, :corporation, corporation_id, priority})
  end

  @doc """
  Warms alliance data for a specific alliance ID.

  ## Parameters
  - alliance_id: EVE alliance ID
  - priority: Warming priority (default: :medium)

  ## Returns
  {:ok, job_id} | {:error, reason}
  """
  @spec warm_alliance(integer() | String.t(), warming_priority()) ::
          {:ok, String.t()} | {:error, term()}
  def warm_alliance(alliance_id, priority \\ :medium) do
    GenServer.call(__MODULE__, {:queue_job, :alliance, alliance_id, priority})
  end

  @doc """
  Warms system data for a specific system ID.

  ## Parameters
  - system_id: EVE system ID
  - priority: Warming priority (default: :medium)

  ## Returns
  {:ok, job_id} | {:error, reason}
  """
  @spec warm_system(integer() | String.t(), warming_priority()) ::
          {:ok, String.t()} | {:error, term()}
  def warm_system(system_id, priority \\ :medium) do
    GenServer.call(__MODULE__, {:queue_job, :system, system_id, priority})
  end

  @doc """
  Executes a warming strategy by name.

  ## Parameters
  - strategy_name: Name of the warming strategy
  - priority: Warming priority (default: :medium)

  ## Returns
  {:ok, job_ids} | {:error, reason}
  """
  @spec warm_strategy(atom(), warming_priority()) :: {:ok, [String.t()]} | {:error, term()}
  def warm_strategy(strategy_name, priority \\ :medium) do
    GenServer.call(__MODULE__, {:execute_strategy, strategy_name, priority})
  end

  @doc """
  Gets current warming status and statistics.

  ## Returns
  Map containing warming status and statistics
  """
  @spec get_status() :: map()
  def get_status do
    GenServer.call(__MODULE__, :get_status)
  end

  @doc """
  Gets warming job history.

  ## Returns
  List of completed warming jobs
  """
  @spec get_job_history() :: [warming_job()]
  def get_job_history do
    GenServer.call(__MODULE__, :get_job_history)
  end

  @doc """
  Forces execution of startup warming strategies.

  ## Returns
  :ok
  """
  @spec force_startup_warming() :: :ok
  def force_startup_warming do
    GenServer.call(__MODULE__, :force_startup_warming)
  end

  @doc """
  Clears the warming queue.

  ## Returns
  :ok
  """
  @spec clear_queue() :: :ok
  def clear_queue do
    GenServer.call(__MODULE__, :clear_queue)
  end

  # GenServer callbacks

  @impl GenServer
  def init(opts) do
    config = Map.merge(@default_config, Map.new(opts))

    state = %{
      config: config,
      warming_active: false,
      job_queue: :queue.new(),
      running_jobs: %{},
      completed_jobs: [],
      failed_jobs: [],
      job_counter: 0,
      startup_warming_done: false
    }

    # Schedule startup warming if enabled
    if config.startup_warming do
      Process.send_after(self(), :startup_warming, 1000)
    end

    Logger.info("Cache warmer initialized")
    {:ok, state}
  end

  @impl GenServer
  def handle_call(:start_warming, _from, state) do
    if state.warming_active do
      {:reply, :ok, state}
    else
      schedule_warming(state.config.warming_interval)
      new_state = %{state | warming_active: true}
      Logger.info("Cache warming started")
      {:reply, :ok, new_state}
    end
  end

  @impl GenServer
  def handle_call(:stop_warming, _from, state) do
    new_state = %{state | warming_active: false}
    Logger.info("Cache warming stopped")
    {:reply, :ok, new_state}
  end

  @impl GenServer
  def handle_call({:queue_job, type, data, priority}, _from, state) do
    if :queue.len(state.job_queue) >= state.config.queue_size_limit do
      {:reply, {:error, :queue_full}, state}
    else
      {job_id, new_state} = create_and_queue_job(type, data, priority, state)

      # Try to process jobs immediately if warming is active
      if state.warming_active do
        Process.send_after(self(), :process_jobs, 100)
      end

      {:reply, {:ok, job_id}, new_state}
    end
  end

  @impl GenServer
  def handle_call({:execute_strategy, strategy_name, priority}, _from, state) do
    case WarmingStrategies.execute_strategy(strategy_name) do
      {:ok, warming_items} ->
        {job_ids, new_state} = queue_multiple_jobs(warming_items, priority, state)

        # Try to process jobs immediately if warming is active
        if state.warming_active do
          Process.send_after(self(), :process_jobs, 100)
        end

        {:reply, {:ok, job_ids}, new_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl GenServer
  def handle_call(:get_status, _from, state) do
    status = build_status_response(state)
    {:reply, status, state}
  end

  @impl GenServer
  def handle_call(:get_job_history, _from, state) do
    history = state.completed_jobs ++ state.failed_jobs
    {:reply, history, state}
  end

  @impl GenServer
  def handle_call(:force_startup_warming, _from, state) do
    Process.send_after(self(), :startup_warming, 100)
    {:reply, :ok, state}
  end

  @impl GenServer
  def handle_call(:clear_queue, _from, state) do
    new_state = %{state | job_queue: :queue.new()}
    Logger.info("Cache warming queue cleared")
    {:reply, :ok, new_state}
  end

  @impl GenServer
  def handle_info(:startup_warming, state) do
    if state.startup_warming_done do
      {:noreply, state}
    else
      Logger.info("Starting cache warming for critical data")

      # Execute startup warming strategies
      {_job_ids, new_state} = execute_startup_strategies(state)

      # Mark startup warming as done
      new_state = %{new_state | startup_warming_done: true}

      # Start regular warming if not already started
      new_state =
        if new_state.warming_active do
          new_state
        else
          schedule_warming(state.config.warming_interval)
          %{new_state | warming_active: true}
        end

      {:noreply, new_state}
    end
  end

  @impl GenServer
  def handle_info(:warming_cycle, state) do
    if state.warming_active do
      # Execute periodic warming strategies
      {_job_ids, new_state} = execute_periodic_strategies(state)

      # Process queued jobs
      Process.send_after(self(), :process_jobs, 100)

      # Schedule next warming cycle
      schedule_warming(state.config.warming_interval)

      {:noreply, new_state}
    else
      {:noreply, state}
    end
  end

  @impl GenServer
  def handle_info(:process_jobs, state) do
    new_state = process_pending_jobs(state)
    {:noreply, new_state}
  end

  @impl GenServer
  def handle_info({:job_completed, job_id, result}, state) do
    new_state = handle_job_completion(job_id, result, state)

    # Continue processing jobs if queue is not empty
    if not :queue.is_empty(new_state.job_queue) and
         map_size(new_state.running_jobs) < state.config.max_concurrent_jobs do
      Process.send_after(self(), :process_jobs, 100)
    end

    {:noreply, new_state}
  end

  @impl GenServer
  def handle_info({:job_failed, job_id, error}, state) do
    new_state = handle_job_failure(job_id, error, state)

    # Continue processing jobs
    if not :queue.is_empty(new_state.job_queue) and
         map_size(new_state.running_jobs) < state.config.max_concurrent_jobs do
      Process.send_after(self(), :process_jobs, 100)
    end

    {:noreply, new_state}
  end

  @impl GenServer
  def handle_info({ref, result}, state) when is_reference(ref) do
    # Handle Task completion
    case find_job_by_ref(ref, state.running_jobs) do
      {job_id, {_job, _task}} ->
        # Process the task result
        case result do
          {:ok, job_result} ->
            new_state = handle_job_completion(job_id, job_result, state)
            {:noreply, new_state}

          {:error, reason} ->
            new_state = handle_job_failure(job_id, reason, state)
            {:noreply, new_state}
        end

      nil ->
        # Unknown task reference, ignore
        {:noreply, state}
    end
  end

  @impl GenServer
  def handle_info({:DOWN, ref, :process, _pid, _reason}, state) when is_reference(ref) do
    # Handle Task process DOWN message - these are normal for completed tasks
    {:noreply, state}
  end

  @impl GenServer
  def handle_info({:job_timeout, job_id}, state) do
    case Map.get(state.running_jobs, job_id) do
      {_job, task} ->
        # Kill the task
        Task.shutdown(task, :brutal_kill)

        # Handle as failure
        new_state = handle_job_failure(job_id, :timeout, state)
        {:noreply, new_state}

      nil ->
        # Job already completed, ignore timeout
        {:noreply, state}
    end
  end

  # Private functions

  defp schedule_warming(interval) do
    Process.send_after(self(), :warming_cycle, interval)
  end

  defp create_and_queue_job(type, data, priority, state) do
    job_id = generate_job_id(state)

    job = %{
      id: job_id,
      type: type,
      data: data,
      priority: priority,
      created_at: System.monotonic_time(:millisecond),
      started_at: nil,
      completed_at: nil,
      status: :pending,
      error: nil
    }

    new_queue = :queue.in(job, state.job_queue)
    new_state = %{state | job_queue: new_queue, job_counter: state.job_counter + 1}

    {job_id, new_state}
  end

  defp queue_multiple_jobs(warming_items, priority, state) do
    {job_ids, new_state} =
      Enum.reduce(warming_items, {[], state}, fn {type, data}, {acc_ids, acc_state} ->
        {job_id, updated_state} = create_and_queue_job(type, data, priority, acc_state)
        {[job_id | acc_ids], updated_state}
      end)

    {Enum.reverse(job_ids), new_state}
  end

  defp execute_startup_strategies(state) do
    startup_strategies = WarmingStrategies.get_startup_strategies()

    Enum.reduce(startup_strategies, {[], state}, fn strategy_name, {acc_ids, acc_state} ->
      case WarmingStrategies.execute_strategy(strategy_name) do
        {:ok, warming_items} ->
          {job_ids, new_state} = queue_multiple_jobs(warming_items, :high, acc_state)
          {acc_ids ++ job_ids, new_state}

        {:error, reason} ->
          Logger.warning(
            "Failed to execute startup strategy #{strategy_name}: #{inspect(reason)}"
          )

          {acc_ids, acc_state}
      end
    end)
  end

  defp execute_periodic_strategies(state) do
    periodic_strategies = WarmingStrategies.get_periodic_strategies()

    Enum.reduce(periodic_strategies, {[], state}, fn strategy_name, {acc_ids, acc_state} ->
      case WarmingStrategies.execute_strategy(strategy_name) do
        {:ok, warming_items} ->
          {job_ids, new_state} = queue_multiple_jobs(warming_items, :medium, acc_state)
          {acc_ids ++ job_ids, new_state}

        {:error, reason} ->
          Logger.warning(
            "Failed to execute periodic strategy #{strategy_name}: #{inspect(reason)}"
          )

          {acc_ids, acc_state}
      end
    end)
  end

  defp process_pending_jobs(state) do
    available_slots = state.config.max_concurrent_jobs - map_size(state.running_jobs)

    if available_slots > 0 and not :queue.is_empty(state.job_queue) do
      process_jobs_batch(state, available_slots)
    else
      state
    end
  end

  defp process_jobs_batch(state, slots_available) do
    Enum.reduce(1..slots_available, state, fn _, acc_state ->
      if :queue.is_empty(acc_state.job_queue) do
        acc_state
      else
        {{:value, job}, new_queue} = :queue.out(acc_state.job_queue)
        updated_state = %{acc_state | job_queue: new_queue}
        start_job(job, updated_state)
      end
    end)
  end

  defp start_job(job, state) do
    # Update job status
    updated_job = %{job | status: :running, started_at: System.monotonic_time(:millisecond)}

    # Start job task
    task =
      Task.async(fn ->
        try do
          result = execute_warming_job(updated_job)
          {:ok, result}
        rescue
          error ->
            {:error, error}
        catch
          :exit, reason ->
            {:error, {:exit, reason}}
        end
      end)

    # Add to running jobs
    new_running_jobs = Map.put(state.running_jobs, job.id, {updated_job, task})

    # Set up timeout
    Process.send_after(self(), {:job_timeout, job.id}, state.config.warming_timeout)

    %{state | running_jobs: new_running_jobs}
  end

  defp execute_warming_job(job) do
    case job.type do
      :character ->
        warm_character_data(job.data)

      :corporation ->
        warm_corporation_data(job.data)

      :alliance ->
        warm_alliance_data(job.data)

      :system ->
        warm_system_data(job.data)

      _ ->
        {:error, :unknown_job_type}
    end
  end

  defp warm_character_data(character_id) do
    # Check if already cached
    case Facade.get_character(character_id) do
      {:ok, _data} ->
        {:ok, :already_cached}

      {:error, :not_found} ->
        # Fetch from ESI and cache
        case fetch_character_from_esi(character_id) do
          {:ok, character_data} ->
            Facade.put_character(character_id, character_data)
            {:ok, :cached}

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  defp warm_corporation_data(corporation_id) do
    case Facade.get_corporation(corporation_id) do
      {:ok, _data} ->
        {:ok, :already_cached}

      {:error, :not_found} ->
        case fetch_corporation_from_esi(corporation_id) do
          {:ok, corporation_data} ->
            Facade.put_corporation(corporation_id, corporation_data)
            {:ok, :cached}

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  defp warm_alliance_data(alliance_id) do
    case Facade.get_alliance(alliance_id) do
      {:ok, _data} ->
        {:ok, :already_cached}

      {:error, :not_found} ->
        case fetch_alliance_from_esi(alliance_id) do
          {:ok, alliance_data} ->
            Facade.put_alliance(alliance_id, alliance_data)
            {:ok, :cached}

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  defp warm_system_data(system_id) do
    case Facade.get_system(system_id) do
      {:ok, _data} ->
        {:ok, :already_cached}

      {:error, :not_found} ->
        case fetch_system_from_esi(system_id) do
          {:ok, system_data} ->
            Facade.put_system(system_id, system_data)
            {:ok, :cached}

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  # These would integrate with the existing ESI service
  defp fetch_character_from_esi(character_id) do
    WandererNotifier.ESI.Service.get_character(character_id)
  end

  defp fetch_corporation_from_esi(corporation_id) do
    WandererNotifier.ESI.Service.get_corporation_info(corporation_id)
  end

  defp fetch_alliance_from_esi(alliance_id) do
    WandererNotifier.ESI.Service.get_alliance_info(alliance_id)
  end

  defp fetch_system_from_esi(system_id) do
    WandererNotifier.ESI.Service.get_system(system_id)
  end

  defp find_job_by_ref(ref, running_jobs) do
    Enum.find_value(running_jobs, fn {job_id, {job, task}} ->
      if task.ref == ref do
        {job_id, {job, task}}
      else
        nil
      end
    end)
  end

  defp handle_job_completion(job_id, _result, state) do
    case Map.get(state.running_jobs, job_id) do
      {job, task} ->
        Task.shutdown(task, :brutal_kill)

        completed_job = %{
          job
          | status: :completed,
            completed_at: System.monotonic_time(:millisecond)
        }

        # Move to completed jobs
        new_running_jobs = Map.delete(state.running_jobs, job_id)
        new_completed_jobs = [completed_job | state.completed_jobs]

        # Record metrics
        duration = completed_job.completed_at - completed_job.started_at
        Metrics.record_operation_time(:put, duration)

        %{state | running_jobs: new_running_jobs, completed_jobs: new_completed_jobs}

      nil ->
        # Job not found in running jobs
        state
    end
  end

  defp handle_job_failure(job_id, error, state) do
    case Map.get(state.running_jobs, job_id) do
      {job, task} ->
        Task.shutdown(task, :brutal_kill)

        failed_job = %{
          job
          | status: :failed,
            completed_at: System.monotonic_time(:millisecond),
            error: error
        }

        # Move to failed jobs
        new_running_jobs = Map.delete(state.running_jobs, job_id)
        new_failed_jobs = [failed_job | state.failed_jobs]

        Logger.warning("Cache warming job failed", job_id: job_id, error: inspect(error))

        %{state | running_jobs: new_running_jobs, failed_jobs: new_failed_jobs}

      nil ->
        # Job not found in running jobs
        state
    end
  end

  defp generate_job_id(state) do
    "job_#{state.job_counter + 1}_#{System.unique_integer([:positive])}"
  end

  defp build_status_response(state) do
    %{
      warming_active: state.warming_active,
      startup_warming_done: state.startup_warming_done,
      queue_size: :queue.len(state.job_queue),
      running_jobs: map_size(state.running_jobs),
      completed_jobs: length(state.completed_jobs),
      failed_jobs: length(state.failed_jobs),
      max_concurrent_jobs: state.config.max_concurrent_jobs,
      configuration: state.config
    }
  end
end
