defmodule WandererNotifierWeb.Plugs.ConditionalLogger do
  @moduledoc """
  A custom plug that conditionally logs requests, filtering out health check endpoints.
  """

  @behaviour Plug
  require Logger

  @health_check_paths ["/api/health", "/health", "/api/status"]

  def init(opts), do: opts

  def call(conn, _opts) do
    if should_log?(conn) do
      Plug.Logger.call(conn, Plug.Logger.init([]))
    else
      conn
    end
  end

  defp should_log?(%Plug.Conn{request_path: path}) do
    path not in @health_check_paths
  end
end
