defmodule WandererNotifier.Infrastructure.ConnectionHealthService do
  @moduledoc """
  Simplified connection health monitoring service.
  This module provides a lightweight interface for monitoring WebSocket and SSE connections
  without the complexity of the full Integration module. It only tracks connection health
  and status, delegating to the existing ConnectionMonitor.
  """

  use Supervisor
  require Logger

  alias WandererNotifier.Infrastructure.Messaging.ConnectionMonitor

  @doc """
  Starts the connection health service supervisor.
  """
  def start_link(opts \\ []) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    children = [
      # Only start the ConnectionMonitor
      {ConnectionMonitor, []}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  # ========================================================================
  # Public API - Simple delegation to ConnectionMonitor
  # ========================================================================

  @doc """
  Registers a WebSocket connection for monitoring.
  """
  @spec register_websocket_connection(String.t(), map()) :: :ok | {:error, term()}
  def register_websocket_connection(connection_id, metadata \\ %{}) do
    ConnectionMonitor.register_connection(connection_id, :websocket, metadata)
  end

  @doc """
  Registers an SSE connection for monitoring.
  """
  @spec register_sse_connection(String.t(), map()) :: :ok | {:error, term()}
  def register_sse_connection(connection_id, metadata \\ %{}) do
    ConnectionMonitor.register_connection(connection_id, :sse, metadata)
  end

  @doc """
  Updates connection health status.
  """
  @spec update_connection_health(String.t(), atom(), map()) :: :ok
  def update_connection_health(connection_id, status, _metadata \\ %{}) do
    ConnectionMonitor.update_connection_status(connection_id, status)

    # Log significant status changes
    if status in [:connected, :failed, :disconnected] do
      Logger.debug("[Connection] #{connection_id}: #{status}")
    end

    :ok
  end

  @doc """
  Gets the current health status of all connections.
  """
  @spec get_health_status() :: %{websocket: list(), sse: list()}
  def get_health_status do
    case ConnectionMonitor.get_connections() do
      connections when is_list(connections) ->
        %{
          websocket: Enum.filter(connections, &(&1.type == :websocket)),
          sse: Enum.filter(connections, &(&1.type == :sse))
        }

      _ ->
        %{websocket: [], sse: []}
    end
  end

  @doc """
  Checks if the service is running.
  """
  @spec running?() :: boolean()
  def running? do
    Process.whereis(__MODULE__) != nil
  end
end
