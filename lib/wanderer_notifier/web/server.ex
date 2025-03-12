defmodule WandererNotifier.Web.Server do
  @moduledoc """
  Web server for the WandererNotifier dashboard.
  """
  use GenServer
  require Logger
  alias WandererNotifier.Web.Router

  @default_port 4000

  # Client API

  @doc """
  Starts the web server.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  # Server Implementation

  @impl true
  def init(opts) do
    port = Keyword.get(opts, :port, @default_port)
    
    Logger.info("Starting web server on port #{port}...")
    
    case start_server(port) do
      {:ok, pid} ->
        Logger.info("Web server started successfully on port #{port}")
        {:ok, %{server_pid: pid, port: port}}
        
      {:error, reason} ->
        Logger.error("Failed to start web server: #{inspect(reason)}")
        {:stop, reason}
    end
  end

  @impl true
  def terminate(_reason, %{server_pid: pid}) do
    Logger.info("Stopping web server...")
    
    if Process.alive?(pid) do
      Process.exit(pid, :normal)
    end
    
    :ok
  end

  # Helper functions

  defp start_server(port) do
    Plug.Cowboy.http(Router, [], port: port)
  end
end 