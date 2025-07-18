defmodule WandererNotifier.Realtime.ConnectionMonitor do
  @moduledoc """
  Connection health monitoring GenServer for real-time connections.

  Tracks WebSocket and SSE connections, monitors their health, and provides
  metrics about connection quality, uptime, and performance.
  """

  use GenServer
  require Logger

  alias WandererNotifier.Realtime.HealthChecker

  # Connection states
  @states [:disconnected, :connecting, :connected, :reconnecting, :failed]

  defmodule Connection do
    @moduledoc """
    Represents a monitored connection.
    """

    defstruct [
      :id,
      :type,
      :pid,
      :status,
      :quality,
      :connected_at,
      :last_heartbeat,
      :ping_time,
      :uptime_percentage,
      :metrics
    ]

    @type t :: %__MODULE__{
            id: String.t(),
            type: :websocket | :sse,
            pid: pid() | nil,
            status: atom(),
            quality: atom(),
            connected_at: DateTime.t() | nil,
            last_heartbeat: DateTime.t() | nil,
            ping_time: non_neg_integer() | nil,
            uptime_percentage: float(),
            metrics: map()
          }
  end

  # Client API

  @doc """
  Starts the connection monitor.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Registers a new connection for monitoring.

  Can be called with either a PID directly or a metadata map containing a :pid key.
  """
  def register_connection(id, type, pid_or_metadata)

  def register_connection(id, type, pid) when type in [:websocket, :sse] and is_pid(pid) do
    GenServer.cast(__MODULE__, {:register_connection, id, type, pid})
  end

  def register_connection(id, type, metadata)
      when type in [:websocket, :sse] and is_map(metadata) do
    pid = Map.get(metadata, :pid)

    if is_pid(pid) do
      GenServer.cast(__MODULE__, {:register_connection, id, type, pid})
    else
      Logger.error("Invalid pid in connection metadata", id: id, metadata: inspect(metadata))
    end
  end

  @doc """
  Updates the status of a connection.
  """
  def update_connection_status(id, status) when status in @states do
    GenServer.cast(__MODULE__, {:update_status, id, status})
  end

  @doc """
  Records a heartbeat for a connection.
  """
  def record_heartbeat(id) do
    GenServer.cast(__MODULE__, {:record_heartbeat, id})
  end

  @doc """
  Records ping/pong time for a connection.
  """
  def record_ping(id, ping_time) when is_integer(ping_time) and ping_time >= 0 do
    GenServer.cast(__MODULE__, {:record_ping, id, ping_time})
  end

  @doc """
  Gets the status of all monitored connections.
  """
  def get_connections do
    GenServer.call(__MODULE__, :get_connections)
  end

  @doc """
  Gets the status of a specific connection.
  """
  def get_connection(id) do
    GenServer.call(__MODULE__, {:get_connection, id})
  end

  @doc """
  Gets overall health metrics.
  """
  def get_health_metrics do
    GenServer.call(__MODULE__, :get_health_metrics)
  end

  # Server Implementation

  @impl true
  def init(_opts) do
    Logger.info("Connection monitor started")

    # Schedule periodic health checks
    schedule_health_check()

    state = %{
      connections: %{},
      metrics: %{
        total_connections: 0,
        active_connections: 0,
        failed_connections: 0,
        average_uptime: 0.0,
        average_ping: 0
      }
    }

    {:ok, state}
  end

  @impl true
  def handle_cast({:register_connection, id, type, pid}, state) do
    Logger.info("Registering connection: #{id} (#{type})")

    connection = %Connection{
      id: id,
      type: type,
      pid: pid,
      status: :connecting,
      quality: :good,
      connected_at: nil,
      last_heartbeat: nil,
      ping_time: nil,
      uptime_percentage: 0.0,
      metrics: %{
        connects: 1,
        disconnects: 0,
        heartbeats: 0,
        ping_samples: []
      }
    }

    # Monitor the process
    if pid do
      Process.monitor(pid)
    end

    connections = Map.put(state.connections, id, connection)
    new_state = %{state | connections: connections}
    updated_state = update_global_metrics(new_state)

    {:noreply, updated_state}
  end

  @impl true
  def handle_cast({:update_status, id, status}, state) do
    case Map.get(state.connections, id) do
      nil ->
        Logger.warning("Attempted to update status for unknown connection: #{id}")
        {:noreply, state}

      connection ->
        Logger.debug("Connection #{id} status changed to #{status}")

        updated_connection = %{connection | status: status}

        updated_connection =
          if status == :connected and connection.connected_at == nil do
            connected_connection = %{updated_connection | connected_at: DateTime.utc_now()}
            # Immediately calculate uptime for new connections
            connected_connection
            |> update_connection_quality()
            |> update_uptime_percentage()
          else
            updated_connection
          end

        connections = Map.put(state.connections, id, updated_connection)
        new_state = %{state | connections: connections}
        updated_state = update_global_metrics(new_state)

        {:noreply, updated_state}
    end
  end

  @impl true
  def handle_cast({:record_heartbeat, id}, state) do
    case Map.get(state.connections, id) do
      nil ->
        {:noreply, state}

      connection ->
        now = DateTime.utc_now()
        updated_metrics = Map.update(connection.metrics, :heartbeats, 1, &(&1 + 1))

        updated_connection = %{connection | last_heartbeat: now, metrics: updated_metrics}

        connections = Map.put(state.connections, id, updated_connection)
        {:noreply, %{state | connections: connections}}
    end
  end

  @impl true
  def handle_cast({:record_ping, id, ping_time}, state) do
    case Map.get(state.connections, id) do
      nil ->
        {:noreply, state}

      connection ->
        # Keep last 10 ping samples for averaging
        ping_samples = connection.metrics.ping_samples || []
        updated_samples = Enum.take([ping_time | ping_samples], 10)

        updated_metrics = Map.put(connection.metrics, :ping_samples, updated_samples)
        updated_connection = %{connection | ping_time: ping_time, metrics: updated_metrics}

        connections = Map.put(state.connections, id, updated_connection)
        {:noreply, %{state | connections: connections}}
    end
  end

  @impl true
  def handle_call(:get_connections, _from, state) do
    connections_list = Map.values(state.connections)
    {:reply, {:ok, connections_list}, state}
  end

  @impl true
  def handle_call({:get_connection, id}, _from, state) do
    case Map.get(state.connections, id) do
      nil -> {:reply, {:error, :not_found}, state}
      connection -> {:reply, {:ok, connection}, state}
    end
  end

  @impl true
  def handle_call(:get_health_metrics, _from, state) do
    {:reply, state.metrics, state}
  end

  @impl true
  def handle_info(:health_check, state) do
    # Update connection qualities and uptime
    updated_connections =
      state.connections
      |> Enum.map(fn {id, connection} ->
        updated_connection =
          connection
          |> update_connection_quality()
          |> update_uptime_percentage()

        {id, updated_connection}
      end)
      |> Map.new()

    new_state = %{state | connections: updated_connections}
    updated_state = update_global_metrics(new_state)

    # Schedule next health check
    schedule_health_check()

    {:noreply, updated_state}
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, pid, reason}, state) do
    # Find and update the connection that went down
    {connection_id, _connection} =
      Enum.find(state.connections, fn {_id, conn} -> conn.pid == pid end) || {nil, nil}

    if connection_id do
      Logger.warning("Connection #{connection_id} process died: #{inspect(reason)}")

      updated_connection =
        state.connections[connection_id]
        |> Map.put(:status, :failed)
        |> Map.put(:pid, nil)

      connections = Map.put(state.connections, connection_id, updated_connection)
      new_state = %{state | connections: connections}
      updated_state = update_global_metrics(new_state)

      {:noreply, updated_state}
    else
      {:noreply, state}
    end
  end

  # Private functions

  defp schedule_health_check do
    # 30 seconds
    Process.send_after(self(), :health_check, 30_000)
  end

  defp update_connection_quality(connection) do
    quality = HealthChecker.assess_connection_quality(connection)
    %{connection | quality: quality}
  end

  defp update_uptime_percentage(connection) do
    uptime = HealthChecker.calculate_uptime_percentage(connection)
    %{connection | uptime_percentage: uptime}
  end

  defp update_global_metrics(state) do
    connections = Map.values(state.connections)

    metrics = %{
      total_connections: length(connections),
      active_connections: Enum.count(connections, &(&1.status == :connected)),
      failed_connections: Enum.count(connections, &(&1.status == :failed)),
      average_uptime: calculate_average_uptime(connections),
      average_ping: calculate_average_ping(connections)
    }

    %{state | metrics: metrics}
  end

  defp calculate_average_uptime([]), do: 0.0

  defp calculate_average_uptime(connections) do
    total_uptime = Enum.reduce(connections, 0.0, &(&1.uptime_percentage + &2))
    total_uptime / length(connections)
  end

  defp calculate_average_ping(connections) do
    ping_times =
      connections
      |> Enum.filter(&(!is_nil(&1.ping_time)))
      |> Enum.map(& &1.ping_time)

    case ping_times do
      [] -> 0
      times -> (Enum.sum(times) / length(times)) |> round()
    end
  end
end
