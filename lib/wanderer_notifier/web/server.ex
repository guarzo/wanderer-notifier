defmodule WandererNotifier.Web.Server do
  @moduledoc """
  Web server for the WandererNotifier dashboard.
  """
  use GenServer
  require Logger

  alias WandererNotifier.Logger.Logger, as: AppLogger
  alias WandererNotifier.Web.Router
  alias WandererNotifier.Constants

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

    {:ok, %{port: port, running: false, server_ref: nil}, {:continue, :start_server}}
  end

  @impl true
  def handle_continue(:start_server, state) do
    case start_server(state.port) do
      {:ok, server_ref} ->
        AppLogger.startup_info("✅ Web server started on port #{state.port}")
        schedule_heartbeat()
        {:noreply, %{state | running: true, server_ref: server_ref}}

      {:error, reason} ->
        AppLogger.startup_error("❌ Failed to start web server",
          error: inspect(reason)
        )

        {:stop, reason, state}
    end
  end

  @impl true
  def handle_call(:status, _from, state) do
    {:reply, state.running, state}
  end

  @impl true
  def handle_info(:heartbeat, state) do
    # Check if we can make a request to the health endpoint
    case check_health_endpoint(state.port) do
      :ok ->
        AppLogger.startup_debug("Web server heartbeat check passed")

      {:error, reason} ->
        AppLogger.startup_error("Web server heartbeat check failed",
          reason: inspect(reason)
        )
    end

    schedule_heartbeat()
    {:noreply, state}
  end

  @impl true
  def terminate(_reason, %{server_ref: ref} = _state) when not is_nil(ref) do
    AppLogger.startup_debug("Stopping web server")
    # Plug.Cowboy returns a reference, not a pid, so we just log the shutdown
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
    Process.send_after(self(), :heartbeat, Constants.web_server_heartbeat_interval())
  end

  defp check_health_endpoint(port) do
    url = "http://localhost:#{port}/health"

    case :httpc.request(:get, {String.to_charlist(url), []}, [{:timeout, 5000}], []) do
      {:ok, {{_, 200, _}, _, _}} ->
        :ok

      {:ok, {{_, status, _}, _, _}} ->
        {:error, {:bad_status, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
