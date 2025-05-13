defmodule WandererNotifier.Web.Server do
  @moduledoc """
  Web server for the WandererNotifier dashboard.
  """
  use GenServer
  require Logger

  alias WandererNotifier.Logger.Logger, as: AppLogger
  alias WandererNotifier.Web.Router

  # Client API

  @doc """
  Starts the web server.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Check if the web server is running
  """
  def running? do
    GenServer.call(__MODULE__, :status)
  end

  # Server Implementation

  @impl true
  def init(_opts) do
    # Get port from configuration
    port = WandererNotifier.Config.port()

    AppLogger.startup_debug("Starting web server", port: port)

    case start_server(port) do
      {:ok, pid} ->
        AppLogger.startup_info("🌐 Web server ready on port #{port}")
        # Schedule a heartbeat check
        schedule_heartbeat()
        {:ok, %{server_pid: pid, port: port, running: true}}

      {:error, reason} ->
        AppLogger.startup_error("❌ Failed to start web server", error: inspect(reason))
        # Try to recover by using a different port
        case start_server(port + 1) do
          {:ok, pid} ->
            AppLogger.startup_info("🌐 Web server started on fallback port #{port + 1}")
            schedule_heartbeat()
            {:ok, %{server_pid: pid, port: port + 1, running: true}}

          {:error, fallback_reason} ->
            AppLogger.startup_error("❌ Failed to start web server on fallback port",
              error: inspect(fallback_reason)
            )

            # Return ok but mark as not running - we'll retry on heartbeat
            schedule_heartbeat()
            {:ok, %{server_pid: nil, port: port, running: false}}
        end
    end
  end

  @impl true
  def handle_call(:status, _from, state) do
    {:reply, state.running, state}
  end

  @impl true
  def handle_info(:heartbeat, %{running: false, port: port} = state) do
    # Try to start server again if it's not running
    case start_server(port) do
      {:ok, pid} ->
        AppLogger.startup_info("🌐 Web server restarted successfully on port #{port}")
        schedule_heartbeat()
        {:noreply, %{state | server_pid: pid, running: true}}

      {:error, _reason} ->
        # Schedule another retry
        schedule_heartbeat()
        {:noreply, state}
    end
  end

  @impl true
  def handle_info(:heartbeat, state) do
    # Check if the server is still alive
    if Process.alive?(state.server_pid) do
      schedule_heartbeat()
      {:noreply, state}
    else
      # Server died, try to restart it
      AppLogger.startup_warn("Web server process died, attempting restart")

      case start_server(state.port) do
        {:ok, pid} ->
          AppLogger.startup_info("🌐 Web server restarted successfully")
          schedule_heartbeat()
          {:noreply, %{state | server_pid: pid, running: true}}

        {:error, reason} ->
          AppLogger.startup_error("❌ Failed to restart web server", error: inspect(reason))
          schedule_heartbeat()
          {:noreply, %{state | server_pid: nil, running: false}}
      end
    end
  end

  @impl true
  def terminate(_reason, %{server_pid: pid} = _state) when is_pid(pid) do
    AppLogger.startup_debug("Stopping web server")

    if Process.alive?(pid) do
      Process.exit(pid, :normal)
    end

    :ok
  end

  @impl true
  def terminate(_reason, _state), do: :ok

  # Helper functions

  defp start_server(port) when is_integer(port) do
    # Use explicit options for binding to all interfaces
    server_opts = [
      port: port,
      ip: {0, 0, 0, 0},
      compress: true,
      protocol_options: [idle_timeout: 60_000]
    ]

    try do
      AppLogger.startup_debug("Attempting to start web server", port: port)
      Plug.Cowboy.http(Router, [], server_opts)
    rescue
      e ->
        AppLogger.startup_error("❌ Exception when starting web server",
          error: Exception.message(e),
          stacktrace: Exception.format_stacktrace(__STACKTRACE__)
        )

        {:error, e}
    catch
      kind, reason ->
        AppLogger.startup_error("❌ Error starting web server",
          kind: kind,
          error: inspect(reason)
        )

        {:error, reason}
    end
  end

  defp schedule_heartbeat do
    # Check every 30 seconds if the server is still running
    Process.send_after(self(), :heartbeat, 30_000)
  end
end
