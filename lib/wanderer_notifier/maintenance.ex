defmodule WandererNotifier.Maintenance do
  @moduledoc """
  Proxy module for WandererNotifier.Services.Maintenance.
  Delegates maintenance functionality to the Services.Maintenance implementation.

  This proxy ensures backward compatibility while the codebase transitions
  to the new namespace structure.
  """
  use GenServer
  require Logger

  alias WandererNotifier.Services.Maintenance, as: MaintenanceImpl
  alias WandererNotifier.Config.Timings

  @doc """
  Starts the maintenance proxy GenServer.

  This proxy will forward messages to the actual implementation in
  WandererNotifier.Services.Maintenance.
  """
  def start_link(opts) do
    Logger.info("Starting Maintenance proxy")
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(opts) do
    # Also ensure the implementation module is started
    case ensure_implementation_started(opts) do
      {:ok, _pid} ->
        Logger.info("Maintenance proxy started, delegating to Services.Maintenance")
        schedule_tick()
        {:ok, %{}}

      {:error, reason} ->
        Logger.error("Failed to start Maintenance implementation: #{inspect(reason)}")
        {:stop, reason}
    end
  end

  @impl true
  def handle_info(:tick, state) do
    # Schedule the next tick
    schedule_tick()

    # Forward to implementation if available
    if Process.whereis(MaintenanceImpl) do
      send(MaintenanceImpl, :tick)
    else
      Logger.warning("Maintenance implementation not available, trying to restart")
      ensure_implementation_started([])
    end

    {:noreply, state}
  end

  # Schedule the next maintenance check
  defp schedule_tick do
    Process.send_after(self(), :tick, Timings.maintenance_interval())
  end

  # Ensure the implementation module is started
  defp ensure_implementation_started(opts) do
    case Process.whereis(MaintenanceImpl) do
      nil ->
        # Start the implementation module if not running
        Logger.info("Starting Maintenance implementation")
        MaintenanceImpl.start_link(opts)

      pid when is_pid(pid) ->
        # Already running
        {:ok, pid}
    end
  end

  @doc """
  Returns the child_spec for this service
  """
  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      type: :worker,
      restart: :permanent,
      shutdown: 500
    }
  end
end
