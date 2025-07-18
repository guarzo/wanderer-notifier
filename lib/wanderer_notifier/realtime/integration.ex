defmodule WandererNotifier.Realtime.Integration do
  @moduledoc """
  Integration module that connects all Sprint 3 real-time processing components
  with the existing WandererNotifier system.

  Provides a unified interface for:
  - Connection monitoring and health tracking
  - Message deduplication across sources
  - Event sourcing pipeline integration
  - Performance metrics collection
  """

  use Supervisor
  require Logger

  alias WandererNotifier.Realtime.{ConnectionMonitor, MessageTracker, Deduplicator, HealthChecker}
  alias WandererNotifier.EventSourcing.{Event, Pipeline}
  alias WandererNotifier.Metrics.{Collector, Dashboard, PerformanceMonitor, EventAnalytics}

  @doc """
  Starts the real-time integration supervisor.
  """
  def start_link(opts \\ []) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Initializes the supervisor with all Sprint 3 components.
  """
  @impl true
  def init(_opts) do
    children = [
      # Connection monitoring components
      {ConnectionMonitor, []},

      # Message deduplication components
      {MessageTracker, []},
      {Deduplicator, []},

      # Event sourcing components
      {Pipeline, []},

      # Metrics and analytics components
      {Collector, []},
      {EventAnalytics, []},
      {PerformanceMonitor, []},
      {Dashboard, []},

      # Integration worker that coordinates everything
      {__MODULE__.Worker, []}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  @doc """
  Registers a WebSocket connection for monitoring.
  """
  def register_websocket_connection(connection_id, metadata \\ %{}) do
    ConnectionMonitor.register_connection(connection_id, :websocket, metadata)
  end

  @doc """
  Registers an SSE connection for monitoring.
  """
  def register_sse_connection(connection_id, metadata \\ %{}) do
    ConnectionMonitor.register_connection(connection_id, :sse, metadata)
  end

  @doc """
  Processes a killmail from WebSocket through the integrated pipeline.
  """
  def process_websocket_killmail(killmail_data) do
    with {:ok, event} <- create_killmail_event(killmail_data, :websocket),
         {:ok, :processed} <- deduplicate_event(event),
         :ok <- track_event_analytics(event),
         :ok <- process_through_pipeline(event) do
      {:ok, event}
    else
      {:ok, :duplicate} ->
        Logger.debug("Duplicate killmail filtered", killmail_id: get_killmail_id(killmail_data))
        {:ok, :duplicate}

      {:error, reason} = error ->
        Logger.error("Failed to process WebSocket killmail", error: inspect(reason))
        error
    end
  end

  @doc """
  Processes an SSE event through the integrated pipeline.
  """
  def process_sse_event(event_type, event_data) do
    with {:ok, event} <- create_sse_event(event_type, event_data),
         {:ok, :processed} <- deduplicate_event(event),
         :ok <- track_event_analytics(event),
         :ok <- process_through_pipeline(event) do
      {:ok, event}
    else
      {:ok, :duplicate} ->
        Logger.debug("Duplicate SSE event filtered", type: event_type)
        {:ok, :duplicate}

      {:error, reason} = error ->
        Logger.error("Failed to process SSE event", type: event_type, error: inspect(reason))
        error
    end
  end

  @doc """
  Updates connection health status.
  """
  def update_connection_health(connection_id, status, metadata \\ %{}) do
    ConnectionMonitor.update_connection_status(connection_id, status)

    # Record metrics if status changed
    if status in [:connected, :disconnected, :failed] do
      record_connection_metric(connection_id, status, metadata)
    end

    :ok
  end

  @doc """
  Records a heartbeat for a connection.
  """
  def record_heartbeat(connection_id) do
    ConnectionMonitor.record_heartbeat(connection_id)
  end

  @doc """
  Gets comprehensive dashboard data.
  """
  def get_dashboard_data do
    Dashboard.get_dashboard_data()
  end

  @doc """
  Gets connection health report.
  """
  def get_connection_health(connection_id) do
    with {:ok, connection} <- ConnectionMonitor.get_connection(connection_id) do
      health_report = HealthChecker.generate_health_report(connection)
      {:ok, health_report}
    end
  end

  @doc """
  Gets all active connections with health status.
  """
  def get_all_connections_health do
    case ConnectionMonitor.get_connections() do
      {:ok, connections} ->
        health_reports = Enum.map(connections, &HealthChecker.generate_health_report/1)
        {:ok, health_reports}

      error ->
        error
    end
  end

  # Private helper functions

  defp create_killmail_event(killmail_data, source) do
    event =
      Event.from_websocket_killmail(killmail_data,
        metadata: %{
          received_at: System.system_time(:millisecond),
          source_type: source
        }
      )

    Event.validate(event)
  end

  defp create_sse_event("system", data) do
    event =
      Event.from_sse_system(data,
        metadata: %{
          received_at: System.system_time(:millisecond),
          source_type: :sse
        }
      )

    Event.validate(event)
  end

  defp create_sse_event("character", data) do
    event =
      Event.from_sse_character(data,
        metadata: %{
          received_at: System.system_time(:millisecond),
          source_type: :sse
        }
      )

    Event.validate(event)
  end

  defp create_sse_event(type, data) do
    event =
      Event.new(type, :sse, data,
        metadata: %{
          received_at: System.system_time(:millisecond),
          source_type: :sse
        }
      )

    Event.validate(event)
  end

  defp deduplicate_event(event) do
    Deduplicator.check_message(event)
  end

  defp track_event_analytics(event) do
    EventAnalytics.record_event(event)
    :ok
  end

  defp process_through_pipeline(event) do
    Pipeline.process_event(event)
    :ok
  end

  defp get_killmail_id(%{killmail_id: id}), do: id
  defp get_killmail_id(%{"killmail_id" => id}), do: id
  defp get_killmail_id(_), do: "unknown"

  defp record_connection_metric(connection_id, status, metadata) do
    # Only trigger collection for significant status changes, not every update
    if status in [:connected, :failed, :disconnected] do
      Collector.collect_now()
    end

    # Log connection status changes
    Logger.info("Connection status changed",
      connection_id: connection_id,
      status: status,
      metadata: metadata
    )
  end

  defmodule Worker do
    @moduledoc """
    Worker process that handles periodic tasks and coordination.
    """

    use GenServer
    require Logger

    # 30 seconds
    @health_check_interval 30_000

    def start_link(opts) do
      GenServer.start_link(__MODULE__, opts, name: __MODULE__)
    end

    @impl true
    def init(_opts) do
      # Schedule periodic health checks
      schedule_health_check()

      Logger.info("Real-time integration worker started")

      {:ok, %{}}
    end

    @impl true
    def handle_info(:health_check, state) do
      perform_health_checks()
      schedule_health_check()
      {:noreply, state}
    end

    defp perform_health_checks do
      # Check all connections
      case ConnectionMonitor.get_connections() do
        {:ok, connections} ->
          check_connections_health(connections)

        _ ->
          :ok
      end

      # Trigger performance check
      PerformanceMonitor.check_performance_now()
    end

    defp check_connections_health(connections) do
      Enum.each(connections, fn connection ->
        health = HealthChecker.assess_connection_quality(connection)

        if health in [:poor, :critical] do
          details = describe_health_issue(connection, health)
          uptime = Float.round(connection.uptime_percentage || 0.0, 2)

          Logger.warning(
            "Connection health degraded: #{connection.id} (#{connection.type}) - Quality: #{health}, Status: #{connection.status}, Uptime: #{uptime}%, Details: #{details}"
          )
        end
      end)
    end

    defp describe_health_issue(connection, health) do
      issues =
        []
        |> check_uptime_issue(connection)
        |> check_heartbeat_issue(connection)
        |> check_connection_status_issue(connection)
        |> check_ping_issue(connection)

      case issues do
        [] -> "Health assessment: #{health}"
        _ -> Enum.join(issues, ", ")
      end
    end

    defp check_uptime_issue(issues, connection) do
      if connection.uptime_percentage < 90.0 do
        ["Low uptime: #{Float.round(connection.uptime_percentage, 1)}%" | issues]
      else
        issues
      end
    end

    defp check_heartbeat_issue(issues, connection) do
      # Only check heartbeat for WebSocket connections after grace period (SSE doesn't have heartbeats)
      if should_check_heartbeat?(connection) do
        ["No heartbeat received after 60s" | issues]
      else
        issues
      end
    end

    defp should_check_heartbeat?(connection) do
      connection.type == :websocket and
        is_nil(connection.last_heartbeat) and
        not is_nil(connection.connected_at) and
        DateTime.diff(DateTime.utc_now(), connection.connected_at, :second) > 60
    end

    defp check_connection_status_issue(issues, connection) do
      if connection.status != :connected do
        ["Connection status: #{connection.status}" | issues]
      else
        issues
      end
    end

    defp check_ping_issue(issues, connection) do
      if connection.ping_time && connection.ping_time > 1000 do
        ["High ping: #{connection.ping_time}ms" | issues]
      else
        issues
      end
    end

    defp schedule_health_check do
      Process.send_after(self(), :health_check, @health_check_interval)
    end
  end
end
