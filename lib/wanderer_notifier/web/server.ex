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

  # Server Implementation

  @impl true
  def init(_opts) do
    # Get port from configuration
    port = WandererNotifier.Config.port()

    AppLogger.startup_debug("Starting web server", port: port)

    case start_server(port) do
      {:ok, pid} ->
        AppLogger.startup_info("🌐 Web server ready on port #{port}")
        {:ok, %{server_pid: pid, port: port}}

      {:error, reason} ->
        AppLogger.startup_error("❌ Failed to start web server", error: inspect(reason))
        {:stop, reason}
    end
  end

  @impl true
  def terminate(_reason, %{server_pid: pid}) do
    AppLogger.startup_debug("Stopping web server")

    if Process.alive?(pid) do
      Process.exit(pid, :normal)
    end

    :ok
  end

  # Helper functions

  defp start_server(port) when is_integer(port) do
    Plug.Cowboy.http(Router, [], port: port, ip: {0, 0, 0, 0})
  end
end
