defmodule WandererNotifier.ChartService.ChartServiceManager do
  @moduledoc """
  Manages the Node.js chart service process.
  
  This module is responsible for starting, monitoring, and restarting
  the Node.js chart service process when needed. It ensures that the
  chart service is available for generating charts.
  """
  use GenServer
  require Logger

  @node_chart_service_path "chart-service"
  @default_port 3001
  @restart_delay 5000 # 5 seconds between restart attempts
  @max_restart_attempts 5

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
    Logger.info("Chart Service Manager initialized with port #{port}")
    
    # Only start the chart service if chart functionality is enabled
    if WandererNotifier.Core.Config.charts_enabled?() do
      Logger.info("Charts functionality is enabled, starting chart service...")
      # Schedule a delayed start to ensure application is fully initialized
      Process.send_after(self(), :start_chart_service, 1000)
    else
      Logger.warning("Charts functionality is disabled. Chart service will not start.")
    end
    
    {:ok, %{
      port: port,
      process: nil,
      url: "http://localhost:#{port}",
      status: if(WandererNotifier.Core.Config.charts_enabled?(), do: :starting, else: :disabled),
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
    # Stop existing process if running
    if process_alive?(state.process, state) do
      Logger.info("Stopping Node.js chart service process")
      stop_process(state.process)
    end
    
    # Start a new process
    Logger.info("Manually restarting Node.js chart service")
    {:ok, process} = start_chart_service_process(state.port)
    
    new_state = %{state | 
      process: process, 
      status: :running, 
      restart_attempts: 0,
      last_started_at: DateTime.utc_now()
    }
    
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call(:get_url, _from, state) do
    {:reply, state.url, state}
  end

  @impl true
  def handle_info(:start_chart_service, state) do
    # Check if charts functionality is enabled
    if WandererNotifier.Core.Config.charts_enabled?() do
      Logger.info("Starting Node.js chart service on port #{state.port}")
      
      case start_chart_service_process(state.port) do
        {:ok, process} ->
          # Schedule a health check
          schedule_health_check()
          
          {:noreply, %{state | 
            process: process, 
            status: :running, 
            last_started_at: DateTime.utc_now()
          }}
          
        {:error, reason} ->
          Logger.error("Failed to start Node.js chart service: #{inspect(reason)}")
          # Schedule a restart attempt
          schedule_restart()
          
          {:noreply, %{state | status: :failed}}
      end
    else
      Logger.info("Charts functionality is disabled. Skipping chart service start.")
      {:noreply, %{state | status: :disabled}}
    end
  end
  
  # Handle data messages from the port
  @impl true
  def handle_info({port, {:data, _data}}, %{process: port} = state) do
    # Just ignore data messages from the port
    {:noreply, state}
  end

  @impl true
  def handle_info(:health_check, state) do
    # Check if the process is still alive
    is_alive = process_alive?(state.process, state)
    
    if is_alive do
      Logger.debug("Node.js chart service is running")
      # Service is healthy
      schedule_health_check()
      {:noreply, %{state | status: :running}}
    else
      Logger.warning("Node.js chart service process is not running")
      # Process died, restart it
      schedule_restart()
      {:noreply, %{state | status: :stopped}}
    end
  end

  @impl true
  def handle_info(:restart_chart_service, state) do
    # Only attempt to restart if charts are enabled
    if WandererNotifier.Core.Config.charts_enabled?() do
      if state.restart_attempts >= @max_restart_attempts do
        Logger.error("Maximum restart attempts (#{@max_restart_attempts}) reached for Node.js chart service")
        # Reset restart attempts but keep status as failed
        {:noreply, %{state | restart_attempts: 0, status: :failed}}
      else
        Logger.info("Attempting to restart Node.js chart service (attempt #{state.restart_attempts + 1})")
        
        # Stop existing process if still running
        if process_alive?(state.process, state) do
          stop_process(state.process)
        end
        
        case start_chart_service_process(state.port) do
          {:ok, process} ->
            # Restart successful, reset attempts and schedule health check
            schedule_health_check()
            
            {:noreply, %{state | 
              process: process, 
              status: :running, 
              restart_attempts: 0,
              last_started_at: DateTime.utc_now()
            }}
            
          {:error, reason} ->
            Logger.error("Failed to restart Node.js chart service: #{inspect(reason)}")
            # Increment restart attempts and schedule another attempt
            schedule_restart()
            
            {:noreply, %{state | 
              status: :failed, 
              restart_attempts: state.restart_attempts + 1
            }}
        end
      end
    else
      Logger.info("Charts functionality is disabled. Not restarting chart service.")
      {:noreply, %{state | status: :disabled}}
    end
  end

  # Private helpers

  defp get_configured_port do
    Application.get_env(:wanderer_notifier, :chart_service_port, @default_port)
  end

  defp start_chart_service_process(port) do
    try do
      service_path = Path.join(File.cwd!(), @node_chart_service_path)
      # Path to the script (just for logging)
      _script_path = Path.join(service_path, "chart-generator.js")
      
      # First, kill any existing Node.js chart services running on the same port
      cleanup_cmd = "pkill -f 'node chart-generator.js' || true"
      System.cmd("bash", ["-c", cleanup_cmd])
      
      # Wait briefly to ensure the port is released
      :timer.sleep(500)
      
      # Using a simple Bash command to start the service in the background
      bash_cmd = "cd #{service_path} && export CHART_SERVICE_PORT=#{port} && node chart-generator.js > chart-service.log 2>&1 &"
      
      Logger.info("Starting chart service with bash command: #{bash_cmd}")
      
      # Execute the bash command
      case System.cmd("bash", ["-c", bash_cmd]) do
        {_, 0} ->
          # Successfully started the process
          # Sleep briefly to let the service start
          :timer.sleep(1500)
          
          # Now we need a way to track the process - we'll use a dummy port for now
          # This is not ideal but should work for our purposes
          dummy_port = Port.open({:spawn, "echo"}, [:binary])
          
          # Verify the service is actually running by checking the health endpoint
          case check_service_availability("http://localhost:#{port}") do
            :ok ->
              Logger.info("Chart service successfully started and verified")
              {:ok, dummy_port}
              
            {:error, reason} ->
              Logger.warning("Chart service started but health check failed: #{inspect(reason)}")
              # Return ok anyway, the health check will trigger a restart if needed
              {:ok, dummy_port}
          end
          
        {error, code} ->
          Logger.error("Failed to start chart service. Exit code: #{code}, Error: #{error}")
          {:error, "Failed to start chart service: #{error}"}
      end
    rescue
      e ->
        Logger.error("Failed to start Node.js chart service: #{Exception.message(e)}")
        {:error, "Failed to start Node.js chart service: #{Exception.message(e)}"}
    end
  end

  # Removed unused function

  defp process_alive?(nil, _state), do: false
  defp process_alive?(port, state) when is_port(port) do
    try do
      # For our bash-launched service, we'll check if the service is responding
      # rather than checking the port (since we're using a dummy port)
      url = "http://localhost:#{state.port}"
      # Use the original check_service_availability function with no parameters
      result = check_service_availability(url)
      result == :ok
    rescue
      e -> 
        Logger.error("Error checking if chart service process is alive: #{inspect(e)}")
        false
    catch
      :exit, reason ->
        Logger.error("Exit when checking chart service: #{inspect(reason)}")
        false
    end
  end

  defp stop_process(nil), do: :ok
  defp stop_process(port) when is_port(port) do
    # Try to kill any running Node.js chart service processes
    System.cmd("bash", ["-c", "pkill -f 'node chart-generator.js' || true"])
    
    # Close the dummy port if it's still alive
    if Port.info(port) != nil do
      Port.close(port)
    end
    
    :ok
  end

  defp check_service_availability(url) do
    health_url = "#{url}/health"
    headers = [{"Accept", "application/json"}]
    
    try do
      case :httpc.request(:get, {to_charlist(health_url), headers}, [timeout: 5000], []) do
        {:ok, {{_, 200, _}, _, _}} ->
          :ok
          
        {:ok, {{_, status, _}, _, body}} ->
          Logger.warning("Health check for Node.js chart service returned status #{status}: #{inspect(body)}")
          {:error, "Health check failed with status #{status}"}
          
        {:error, reason} ->
          {:error, reason}
      end
    rescue
      e -> {:error, Exception.message(e)}
    end
  end

  defp schedule_health_check do
    # Check health every 30 seconds
    Process.send_after(self(), :health_check, 30_000)
  end

  defp schedule_restart do
    # Restart after delay
    Process.send_after(self(), :restart_chart_service, @restart_delay)
  end
end