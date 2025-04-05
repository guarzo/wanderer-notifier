defmodule WandererNotifier.ChartService.ChartServiceManager do
  @moduledoc """
  Manages the chart service process, handling its lifecycle and providing access to its URL.
  This module starts and monitors a Node.js chart service process and provides an interface
  to interact with it through GenServer calls.
  """

  use GenServer
  require Logger

  @chart_service_dir Application.compile_env(
                       :wanderer_notifier,
                       :chart_service_dir,
                       "chart-service"
                     )

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def get_url do
    GenServer.call(__MODULE__, :get_url)
  end

  def init(_opts) do
    Process.send_after(self(), :start_chart_service, 0)
    {:ok, %{port_num: 3001, port_process: nil}}
  end

  def handle_call(:get_url, _from, state) do
    {:reply, "http://localhost:#{state.port_num}", state}
  end

  def handle_info(:start_chart_service, state) do
    # Get absolute path
    chart_service_path = Path.expand(@chart_service_dir)

    # Simple command that starts npm in the chart service directory
    cmd =
      "sh -c 'cd #{chart_service_path} && WANDERER_CHART_SERVICE_PORT=#{state.port_num} NODE_ENV=production npm start'"

    Logger.info("[Chart Service] Starting with command: #{cmd}")
    port_process = Port.open({:spawn, cmd}, [:binary, :exit_status, :stderr_to_stdout])
    {:noreply, %{state | port_process: port_process}}
  end

  def handle_info({_port, {:data, data}}, state) do
    Logger.info("[Chart Service] #{data}")
    {:noreply, state}
  end

  def handle_info({_port, {:exit_status, status}}, state) do
    Logger.error(
      "[Chart Service] Chart service exited with status #{status}. Restarting in 5 seconds..."
    )

    Process.send_after(self(), :start_chart_service, 5000)
    {:noreply, %{state | port_process: nil}}
  end

  def handle_info(_, state), do: {:noreply, state}
end
