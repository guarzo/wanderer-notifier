defmodule WandererNotifier.License do
  @moduledoc """
  Proxy module for WandererNotifier.Core.License.
  Delegates calls to the Core.License implementation.
  """
  use GenServer
  require Logger

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(opts) do
    # Forward initialization to the real implementation
    Logger.info("License proxy starting, will delegate to WandererNotifier.Core.License")
    {:ok, opts}
  end

  @impl true
  def handle_call(:status, _from, state) do
    # Forward the call to the real implementation
    result = WandererNotifier.Core.License.status()
    {:reply, result, state}
  end

  @impl true
  def handle_call(:validate, _from, state) do
    # Forward the call to the real implementation
    result = WandererNotifier.Core.License.validate()
    {:reply, result, state}
  end

  @impl true
  def handle_call(:premium, _from, state) do
    # Forward the call to the real implementation
    result = WandererNotifier.Core.License.premium?()
    {:reply, result, state}
  end

  @impl true
  def handle_call({:feature_enabled, feature}, _from, state) do
    # Forward the call to the real implementation
    result = WandererNotifier.Core.License.feature_enabled?(feature)
    {:reply, result, state}
  end

  # Public API functions that forward to the handle_call implementations
  def status do
    GenServer.call(__MODULE__, :status)
  end

  def validate do
    GenServer.call(__MODULE__, :validate)
  end

  def premium? do
    GenServer.call(__MODULE__, :premium)
  end

  def feature_enabled?(feature) do
    GenServer.call(__MODULE__, {:feature_enabled, feature})
  end
end
