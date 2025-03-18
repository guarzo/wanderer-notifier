defmodule WandererNotifier.Maintenance do
  @moduledoc """
  Proxy module for WandererNotifier.Services.Maintenance.
  Delegates all calls to the Services.Maintenance implementation.
  """
  use GenServer
  require Logger

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(opts) do
    # Forward initialization to the real implementation
    Logger.info("Maintenance proxy starting, will delegate to WandererNotifier.Services.Maintenance")
    {:ok, opts}
  end

  @impl true
  def handle_info(:tick, state) do
    # Just forward the message to the real implementation
    send(WandererNotifier.Services.Maintenance, :tick)
    {:noreply, state}
  end

  @doc """
  Returns the child_spec for this service
  """
  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {WandererNotifier.Services.Maintenance, :start_link, [opts]},
      type: :worker,
      restart: :permanent,
      shutdown: 500
    }
  end
end
