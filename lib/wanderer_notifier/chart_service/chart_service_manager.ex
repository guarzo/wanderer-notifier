defmodule WandererNotifier.ChartService.ChartServiceManager do
  @moduledoc """
  Manages the Node.js chart service process.

  This module is responsible for starting, monitoring, and restarting
  the Node.js chart service process when needed. It ensures that the
  chart service is available for generating charts.
  """
  use GenServer
  alias WandererNotifier.Config.Web
  alias WandererNotifier.Logger.Logger, as: AppLogger

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Returns the status of the chart service.
  """
  def status do
    GenServer.call(__MODULE__, :status)
  end

  @doc """
  Manually restarts the chart service.
  """
  def restart do
    GenServer.call(__MODULE__, :restart)
  end

  @doc """
  Returns the URL of the chart service.
  """
  def get_url do
    GenServer.call(__MODULE__, :get_url)
  end

  # Server callbacks

  @impl true
  def init(_opts) do
    # Get the configured port from environment or use default
    port = get_configured_port()

    # Log configuration for debugging
    AppLogger.config_info("Chart Service Manager initialized", port: port)

    # Initialize with service enabled
    AppLogger.config_info("Chart service is enabled")

    {:ok,
     %{
       port: port,
       process: nil,
       url: "http://localhost:#{port}",
       status: :starting,
       restart_attempts: 0,
       last_started_at: nil
     }}
  end

  @impl true
  def handle_call(:status, _from, state) do
    # Check if the process is still running
    is_alive = process_alive?(state.process, state)

    # Update status based on process state
    status = if is_alive, do: :running, else: :stopped

    # Return the status information
    status_info = %{
      status: status,
      port: state.port,
      url: state.url,
      last_started_at: state.last_started_at,
      restart_attempts: state.restart_attempts
    }

    {:reply, status_info, %{state | status: status}}
  end

  @impl true
  def handle_call(:restart, _from, state) do
    # Stop any existing process
    if state.process != nil do
      Port.close(state.process)
    end

    # Start a new process
    case start_chart_service(state) do
      {:ok, new_state} ->
        {:reply, :ok, new_state}

      _ ->
        AppLogger.startup_error("Failed to restart chart service")
        {:reply, :error, state}
    end
  end

  @impl true
  def handle_call(:get_url, _from, state) do
    {:reply, state.url, state}
  end

  @impl true
  def handle_info(:start_chart_service, state) do
    case start_chart_service(state) do
      {:ok, new_state} ->
        # Schedule health checks
        schedule_health_check()
        {:noreply, new_state}

      _ ->
        AppLogger.startup_error("Failed to start chart service")
        {:noreply, state}
    end
  end

  # Handle data messages from the port
  @impl true
  def handle_info({port_in, {:data, _data}}, %{process: port_proc} = state)
      when port_in == port_proc do
    # Just ignore data messages from the port
    {:noreply, state}
  end

  @impl true
  def handle_info(:health_check, state) do
    # Check if the service is responding
    is_alive = process_alive?(state.process, state)

    if is_alive do
      # Service is running, schedule next check
      schedule_health_check()
      {:noreply, %{state | status: :running}}
    else
      # Service is down, try to restart
      AppLogger.startup_warn("Chart service is not responding, attempting restart")
      Process.send_after(self(), :restart_chart_service, 1000)
      {:noreply, %{state | status: :restarting}}
    end
  end

  @impl true
  def handle_info(:restart_chart_service, state) do
    if state.restart_attempts < 3 do
      case start_chart_service(state) do
        {:ok, new_state} ->
          schedule_health_check()
          {:noreply, new_state}

        _ ->
          # Schedule another restart attempt
          Process.send_after(self(), :restart_chart_service, 5000)
          {:noreply, %{state | restart_attempts: state.restart_attempts + 1}}
      end
    else
      AppLogger.startup_error("Chart service failed to start after multiple attempts")
      {:noreply, %{state | status: :failed}}
    end
  end

  # Private helpers

  defp get_configured_port do
    Web.get_chart_service_port()
  end

  defp process_alive?(nil, _state), do: false

  defp process_alive?(port, state) when is_port(port) do
    # For our bash-launched service, we'll check if the service is responding
    # rather than checking the port (since we're using a dummy port)
    url = "http://localhost:#{state.port}"
    # Use the original check_service_availability function with no parameters
    result = check_service_availability(url)
    result == :ok
  rescue
    e ->
      AppLogger.startup_error("Error checking if chart service process is alive",
        error: inspect(e),
        stacktrace: Exception.format_stacktrace(__STACKTRACE__)
      )

      false
  catch
    :exit, reason ->
      AppLogger.startup_error("Exit when checking chart service", error: inspect(reason))
      false
  end

  defp check_service_availability(url) do
    health_url = "#{url}/health"
    headers = [{"Accept", "application/json"}]

    case :httpc.request(:get, {to_charlist(health_url), headers}, [timeout: 5000], []) do
      {:ok, {{_, 200, _}, _, _}} ->
        :ok

      {:ok, {{_, status, _}, _, body}} ->
        AppLogger.startup_warn("Health check for Node.js chart service returned error status",
          status: status,
          body: inspect(body)
        )

        {:error, "Health check failed with status #{status}"}

      {:error, reason} ->
        {:error, reason}
    end
  rescue
    e -> {:error, Exception.message(e)}
  end

  defp start_chart_service(state) do
    AppLogger.startup_info("Starting chart service", port: state.port)

    # Build the command to start the Node.js service
    cmd = "cd chart-service && npm start"

    # Start the port
    port = Port.open({:spawn, cmd}, [:binary, :exit_status])

    # Update state with the new process
    new_state = %{
      state
      | process: port,
        status: :starting,
        last_started_at: DateTime.utc_now(),
        restart_attempts: 0
    }

    {:ok, new_state}
  end

  defp schedule_health_check do
    # Check every 30 seconds
    Process.send_after(self(), :health_check, 30_000)
  end
end
