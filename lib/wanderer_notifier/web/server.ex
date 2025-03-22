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
  def init(_opts) do
    # Read port from config or env, using explicit PORT in environment
    port =
      System.get_env("PORT")
      |> case do
        nil ->
          WandererNotifier.Core.Config.web_port() || @default_port

        str_port ->
          case Integer.parse(str_port) do
            {num, _} -> num
            :error -> @default_port
          end
      end

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
    Plug.Cowboy.http(Router, [], port: port, ip: {0, 0, 0, 0})
  end
end
