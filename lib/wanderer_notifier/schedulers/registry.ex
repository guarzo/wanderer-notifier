defmodule WandererNotifier.Schedulers.Registry do
  @moduledoc """
  Registry for managing all schedulers in the application.

  This module keeps track of all registered schedulers and provides
  utility functions to interact with them collectively.
  """

  use GenServer
  require Logger
alias WandererNotifier.Logger, as: AppLogger

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
    AppLogger.scheduler_info("Initializing Scheduler Registry...")
    {:ok, %{schedulers: []}}
  end

  @impl true
  def handle_cast({:register, scheduler_module}, state) do
    if Enum.member?(state.schedulers, scheduler_module) do
      AppLogger.scheduler_debug("Scheduler #{inspect(scheduler_module)} already registered")
      {:noreply, state}
    else
      AppLogger.scheduler_info("Registering scheduler: #{inspect(scheduler_module)}")
      {:noreply, %{state | schedulers: [scheduler_module | state.schedulers]}}
    end
  end

  @impl true
  def handle_cast(:execute_all, state) do
    AppLogger.scheduler_info("Triggering execution of all registered schedulers")

    Enum.each(state.schedulers, fn scheduler ->
      if function_exported?(scheduler, :execute_now, 0) do
        AppLogger.scheduler_debug("Executing scheduler: #{inspect(scheduler)}")
        scheduler.execute_now()
      else
        AppLogger.scheduler_warn("Scheduler #{inspect(scheduler)} does not implement execute_now/0")
      end
    end)

    {:noreply, state}
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
