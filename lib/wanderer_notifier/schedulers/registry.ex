defmodule WandererNotifier.Schedulers.Registry do
  @moduledoc """
  Registry for managing all schedulers in the application.

  This module keeps track of all registered schedulers and provides
  utility functions to interact with them collectively.
  """

  use GenServer
  alias WandererNotifier.Logger.Logger, as: AppLogger
  alias WandererNotifier.Logger.StartupTracker
  # Client API

  @doc """
  Starts the scheduler registry.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Registers a scheduler module with the registry.
  """
  def register(scheduler_module) do
    GenServer.cast(__MODULE__, {:register, scheduler_module})
  end

  @doc """
  Gets information about all registered schedulers.
  """
  def get_all_schedulers do
    GenServer.call(__MODULE__, :get_all_schedulers)
  end

  @doc """
  Triggers execution of all registered schedulers.
  """
  def execute_all do
    GenServer.cast(__MODULE__, :execute_all)
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    # Use startup tracker if available
    if Process.get(:startup_tracker) do
      StartupTracker.record_event(:scheduler_registry, %{
        status: "initializing"
      })
    else
      AppLogger.scheduler_info("Initializing Scheduler Registry...")
    end

    # Initialize with a counter to track the number of schedulers
    {:ok, %{schedulers: [], enabled_count: 0, disabled_count: 0}}
  end

  @impl true
  def handle_cast({:register, scheduler_module}, state) do
    {enabled_count, disabled_count} =
      if scheduler_module.enabled?() do
        {state.enabled_count + 1, state.disabled_count}
      else
        {state.enabled_count, state.disabled_count + 1}
      end

    # Update state with new scheduler
    new_state = %{
      state
      | schedulers: [scheduler_module | state.schedulers],
        enabled_count: enabled_count,
        disabled_count: disabled_count
    }

    # Log a summary based on certain conditions
    maybe_log_scheduler_summary(length(new_state.schedulers), enabled_count, disabled_count)

    {:noreply, new_state}
  end

  @impl true
  def handle_cast(:execute_all, state) do
    AppLogger.scheduler_info("Triggering execution of all registered schedulers")

    Enum.each(state.schedulers, fn scheduler ->
      if function_exported?(scheduler, :execute_now, 0) do
        AppLogger.scheduler_debug("Executing scheduler: #{inspect(scheduler)}")
        scheduler.execute_now()
      else
        AppLogger.scheduler_warn(
          "Scheduler #{inspect(scheduler)} does not implement execute_now/0"
        )
      end
    end)

    {:noreply, state}
  end

  # Private function to handle logging logic
  defp maybe_log_scheduler_summary(total_count, enabled_count, disabled_count) do
    # Only log scheduler summary when we reach a significant milestone
    # in the registration process (final expected scheduler or at regular intervals)
    if total_count == 6 || (total_count > 0 && rem(total_count, 3) == 0) do
      # Always use the startup tracker to consolidate logs
      if Process.get(:startup_tracker) do
        # Only track the event, it will be logged only once by the supervisor later
        StartupTracker.record_event(:scheduler_status, %{
          total: total_count,
          enabled: enabled_count,
          disabled: disabled_count
        })
      else
        # If no startup tracker, log at debug level to reduce noise
        AppLogger.scheduler_debug(
          "Scheduler registration progress",
          %{total: total_count, enabled: enabled_count, disabled: disabled_count}
        )
      end
    end
  end

  @impl true
  def handle_call(:get_all_schedulers, _from, state) do
    scheduler_info =
      Enum.map(state.schedulers, fn scheduler ->
        %{
          module: scheduler,
          enabled: scheduler.enabled?(),
          config: scheduler.get_config()
        }
      end)

    {:reply, scheduler_info, state}
  end
end
