defmodule WandererNotifier.Services.TPSChartScheduler do
  @moduledoc """
  Proxy module for WandererNotifier.Schedulers.TPSChartScheduler.
  Schedules TPS chart generation and sending to Discord.

  This module is deprecated and will be removed in a future version.
  Use WandererNotifier.Schedulers.TPSChartScheduler instead.
  """
  use GenServer
  require Logger

  alias WandererNotifier.Schedulers.TPSChartScheduler

  def start_link(opts \\ []) do
    Logger.warning("WandererNotifier.Services.TPSChartScheduler is deprecated, use WandererNotifier.Schedulers.TPSChartScheduler instead")
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    Logger.info("Initializing proxy TPS Chart Scheduler (delegating to WandererNotifier.Schedulers.TPSChartScheduler)...")
    {:ok, %{last_run: nil}}
  end

  # Manual trigger for sending charts - delegates to WandererNotifier.Schedulers.TPSChartScheduler
  def send_charts_now do
    Logger.info("Delegating send_charts_now to WandererNotifier.Schedulers.TPSChartScheduler.execute_now")
    TPSChartScheduler.execute_now()
  end

  @impl true
  def handle_cast(:send_charts_now, state) do
    Logger.info("Delegating manually triggered chart generation to WandererNotifier.Schedulers.TPSChartScheduler")
    send_charts_now()
    {:noreply, state}
  end
end