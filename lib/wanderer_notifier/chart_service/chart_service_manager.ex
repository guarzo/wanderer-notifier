defmodule WandererNotifier.ChartService.ChartServiceManager do
  @moduledoc """
  Manages the chart service process, handling its lifecycle and providing access to its URL.
  This module starts and monitors a Node.js chart service process and provides an interface
  to interact with it through GenServer calls.
  """

  use GenServer
  require Logger
  alias WandererNotifier.Logger.Logger, as: AppLogger

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

  @doc """
  Stops the chart service gracefully.
  """
  def stop_chart_service do
    GenServer.call(__MODULE__, :stop_service)
  end

  @doc """
  Requests a restart of the chart service when connection errors occur.
  Returns :ok immediately, the actual restart will happen asynchronously.
  """
  def request_restart do
    if Process.whereis(__MODULE__) do
      GenServer.cast(__MODULE__, :request_restart)
      :ok
    else
      AppLogger.warn("[Chart Service] Cannot restart - chart service manager not running")
      :error
    end
  end

  @impl true
  def init(_opts) do
    # Ensure HTTP client is started
    {:ok, _} = Application.ensure_all_started(:inets)
    {:ok, _} = Application.ensure_all_started(:ssl)

    # First ensure any existing instances are cleaned up
    Process.send_after(self(), :cleanup_existing_service, 0)

    # Get port from config
    port_num =
      Application.get_env(:wanderer_notifier, :chart_service_port, 3001)
      |> to_string()
      |> String.to_integer()

    {:ok, %{port_num: port_num, port_process: nil, pid: nil, status: :initializing}}
  end

  @impl true
  def handle_call(:get_url, _from, state) do
    {:reply, "http://localhost:#{state.port_num}", state}
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    # Return a sanitized state for diagnostics
    state_info = %{
      status: state.status,
      pid: state.pid,
      port_num: state.port_num
    }

    {:reply, state_info, state}
  end

  @impl true
  def handle_call(:stop_service, _from, state) do
    AppLogger.info("[Chart Service] Manual stop requested")
    new_state = do_stop_chart_service(state)
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_cast(:request_restart, state) do
    AppLogger.info("[Chart Service] Restart requested due to connection errors")

    # Stop any existing process first, regardless of state
    new_state = do_stop_chart_service(state)

    # Always schedule a new start attempt, even if there was no process or it was in adopted mode
    Process.send_after(self(), :start_chart_service, 1000)

    {:noreply, %{new_state | pid: nil, status: :restarting}}
  end

  @impl true
  def handle_info(:cleanup_existing_service, state) do
    # First check if there's already a valid chart service running that we can use
    if verify_chart_service(state.port_num) do
      # If there's already a valid chart service, try to find its PID
      case find_process_using_port(state.port_num) do
        {:ok, existing_pid} ->
          AppLogger.info(
            "[Chart Service] Found existing valid chart service with PID #{existing_pid}"
          )

          # Adopt this existing service
          {:noreply, %{state | pid: existing_pid, status: :adopted}}

        _ ->
          AppLogger.warn(
            "[Chart Service] Found valid chart service but couldn't determine PID, starting new one"
          )

          Process.send_after(self(), :start_chart_service, 100)
          {:noreply, state}
      end
    else
      # If no valid chart service found, we'll try to clean up any process using our port
      case find_process_using_port(state.port_num) do
        {:ok, existing_pid} ->
          AppLogger.info(
            "[Chart Service] Found process #{existing_pid} using port #{state.port_num}"
          )

          # Try to terminate gracefully if we found an existing process
          System.cmd("kill", ["-15", "#{existing_pid}"], stderr_to_stdout: true)
          :timer.sleep(500)
          # Now check if it's still running
          if process_running?(existing_pid) do
            AppLogger.warn("[Chart Service] Process still running, forcing termination")
            System.cmd("kill", ["-9", "#{existing_pid}"], stderr_to_stdout: true)
            :timer.sleep(100)
          end

        _ ->
          AppLogger.info("[Chart Service] No process using port #{state.port_num}")
      end

      # Now start our service
      Process.send_after(self(), :start_chart_service, 100)
      {:noreply, state}
    end
  end

  @impl true
  def handle_info(:start_chart_service, state) do
    # Get absolute path
    chart_service_path = Path.expand(@chart_service_dir)

    # Check environment
    env = Application.get_env(:wanderer_notifier, :env, :prod)
    node_env = if env == :dev, do: "development", else: "production"

    # Simple command that starts npm in the chart service directory
    cmd =
      "sh -c 'cd #{chart_service_path} && WANDERER_CHART_SERVICE_PORT=#{state.port_num} NODE_ENV=#{node_env} npm start'"

    AppLogger.startup_info("[Chart Service] Starting with command: #{cmd}")
    port_process = Port.open({:spawn, cmd}, [:binary, :exit_status, :stderr_to_stdout])

    # Schedule a verification check after a suitable delay
    Process.send_after(self(), :verify_chart_service, 5000)

    {:noreply, %{state | port_process: port_process, status: :starting}}
  end

  @impl true
  def handle_info(:verify_chart_service, state) do
    # Verify that the service actually started and is responding
    if verify_chart_service(state.port_num) do
      AppLogger.info(
        "[Chart Service] Verified service is running and healthy after start/restart"
      )
    else
      AppLogger.warn("[Chart Service] Service verification failed after start/restart")
    end

    {:noreply, state}
  end

  @impl true
  def handle_info({_port, {:data, data}}, state) do
    data = String.trim(data)

    # Extract process ID from the output if it contains one
    state =
      case Regex.run(~r/Process started with PID: (\d+)/, data) do
        [_, pid_str] ->
          pid = String.to_integer(pid_str)
          AppLogger.startup_info("[Chart Service] Process ID: #{pid}")
          %{state | pid: pid, status: :running}

        _ ->
          state
      end

    # Check for address in use error
    state =
      case Regex.run(~r/Error: listen EADDRINUSE: address already in use :::(\d+)/, data) do
        [_, port_str] ->
          port = String.to_integer(port_str)
          AppLogger.warn("[Chart Service] Port #{port} already in use")

          # Try to find the process using this port
          case find_process_using_port(port) do
            {:ok, port_pid} ->
              AppLogger.info("[Chart Service] Found process #{port_pid} using port #{port}")

              # Verify this is actually a chart service by testing a connection
              if verify_chart_service(port) do
                AppLogger.info("[Chart Service] Verified and adopting existing chart service")
                # Adopt the existing process instead of starting a new one
                %{state | pid: port_pid, status: :adopted}
              else
                AppLogger.error(
                  "[Chart Service] Process on port #{port} is not a valid chart service"
                )

                %{state | status: :error}
              end

            _ ->
              AppLogger.error("[Chart Service] Could not find process using port #{port}")
              %{state | status: :error}
          end

        _ ->
          state
      end

    AppLogger.info("[Chart Service] #{data}")
    {:noreply, state}
  end

  @impl true
  def handle_info({_port, {:exit_status, status}}, state) do
    # Don't restart immediately if we're in adopted mode - we're using an external service
    if state.status == :adopted do
      AppLogger.info("[Chart Service] Using externally managed service - not restarting")
      {:noreply, %{state | port_process: nil}}
    else
      AppLogger.error(
        "[Chart Service] Chart service exited with status #{status}. Restarting in 5 seconds..."
      )

      Process.send_after(self(), :start_chart_service, 5000)
      {:noreply, %{state | port_process: nil, pid: nil, status: :restarting}}
    end
  end

  @impl true
  def handle_info(_, state), do: {:noreply, state}

  @impl true
  def terminate(reason, state) do
    AppLogger.info(
      "[Chart Service] Terminating chart service manager (reason: #{inspect(reason)})..."
    )

    do_stop_chart_service(state)
    :ok
  end

  # Private function to stop the chart service and return updated state
  defp do_stop_chart_service(%{pid: pid, port_process: port, status: :adopted} = state)
       when is_integer(pid) do
    AppLogger.info("[Chart Service] Service was externally managed (PID #{pid}), not stopping")

    if port && Port.info(port) do
      Port.close(port)
      AppLogger.info("[Chart Service] Port closed successfully")
    end

    %{state | port_process: nil, status: :stopped}
  end

  defp do_stop_chart_service(%{pid: pid, port_process: port} = state) when is_integer(pid) do
    AppLogger.info("[Chart Service] Stopping service with PID #{pid}")

    # First, try to gracefully kill the Node.js process with SIGTERM
    result = System.cmd("kill", ["-15", "#{pid}"], stderr_to_stdout: true)
    AppLogger.debug("[Chart Service] Kill command result: #{inspect(result)}")

    # Give it a moment to shutdown
    :timer.sleep(500)

    # Close the port if it's still open
    if port && Port.info(port) do
      Port.close(port)
      AppLogger.info("[Chart Service] Port closed successfully")
    else
      AppLogger.info("[Chart Service] Port was already closed")
    end

    # Verify if the process is still running
    {ps_output, status} = System.cmd("ps", ["-p", "#{pid}"], stderr_to_stdout: true)

    state =
      case status do
        1 ->
          # Process is already gone (exit status 1 means process not found)
          AppLogger.info("[Chart Service] Process #{pid} gracefully terminated")
          %{state | port_process: nil, pid: nil, status: :stopped}

        0 ->
          # Process still exists, force kill it
          AppLogger.warn("[Chart Service] Process #{pid} still running, forcing termination")
          System.cmd("kill", ["-9", "#{pid}"], stderr_to_stdout: true)
          :timer.sleep(100)
          %{state | port_process: nil, pid: nil, status: :stopped}

        other ->
          AppLogger.error(
            "[Chart Service] Unexpected status from ps command: #{other}, output: #{ps_output}"
          )

          %{state | port_process: nil, pid: nil, status: :unknown}
      end

    state
  end

  defp do_stop_chart_service(%{port_process: port} = state) when port != nil do
    # If we don't have a PID but have a port, just close the port
    if Port.info(port) do
      Port.close(port)
      AppLogger.info("[Chart Service] Port closed")
    end

    %{state | port_process: nil, status: :stopped}
  end

  defp do_stop_chart_service(state) do
    AppLogger.info("[Chart Service] No active process to stop")
    %{state | status: :stopped}
  end

  # Check if a process is running
  defp process_running?(pid) when is_integer(pid) do
    {_, status} = System.cmd("ps", ["-p", "#{pid}"], stderr_to_stdout: true)
    status == 0
  end

  defp process_running?(_), do: false

  # Find process using a specific port
  defp find_process_using_port(port) do
    # First try lsof (most accurate)
    case try_lsof(port) do
      {:ok, pid} -> {:ok, pid}
      # Fallback to netstat if lsof fails
      _ -> try_netstat(port)
    end
  end

  # Try to find process using lsof
  defp try_lsof(port) do
    try do
      # Use lsof to find process using this port
      case System.cmd("lsof", ["-i", ":#{port}", "-t"], stderr_to_stdout: true) do
        {pid_str, 0} ->
          pid_str = String.trim(pid_str)

          if pid_str != "" do
            {:ok, String.to_integer(pid_str)}
          else
            :not_found
          end

        _ ->
          :not_found
      end
    rescue
      # Handle case where lsof is not available
      _ -> :not_found
    end
  end

  # Try to find process using netstat (fallback method)
  defp try_netstat(port) do
    try do
      # Use netstat as a fallback
      {output, 0} = System.cmd("netstat", ["-tulpn"], stderr_to_stdout: true)

      # Parse netstat output to find the process
      case Regex.run(~r/#{port}\s+.*?(\d+)\//, output) do
        [_, pid_str] -> {:ok, String.to_integer(pid_str)}
        _ -> :not_found
      end
    rescue
      # Handle case where netstat fails or isn't available
      _ -> :not_found
    end
  end

  # Verify that a service running on the port is actually our chart service
  defp verify_chart_service(port) do
    url = "http://localhost:#{port}/health"

    try do
      AppLogger.debug("[Chart Service] Attempting to verify chart service at #{url}")

      case :httpc.request(:get, {String.to_charlist(url), []}, [{:timeout, 1000}], []) do
        {:ok, {{_, 200, _}, _, body}} ->
          # Parse response to verify it's our chart service
          response = List.to_string(body)

          case Jason.decode(response) do
            {:ok, %{"status" => "ok", "service" => service}} ->
              AppLogger.debug("[Chart Service] Verified service type: #{service}")
              service == "chart-service"

            {:ok, other} ->
              AppLogger.debug("[Chart Service] Invalid service response: #{inspect(other)}")
              false

            {:error, error} ->
              AppLogger.debug("[Chart Service] Failed to parse response: #{inspect(error)}")
              false
          end

        {:ok, {{_, status, _}, _, _}} ->
          AppLogger.debug("[Chart Service] Service returned non-200 status: #{status}")
          false

        {:error, error} ->
          AppLogger.debug("[Chart Service] HTTP request error: #{inspect(error)}")
          false
      end
    rescue
      exception ->
        AppLogger.debug("[Chart Service] Exception during verification: #{inspect(exception)}")
        false
    end
  end
end
