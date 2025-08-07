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
      start_time = System.monotonic_time()

      Plug.Conn.register_before_send(conn, fn conn ->
        duration = System.monotonic_time() - start_time
        duration_us = System.convert_time_unit(duration, :native, :microsecond)

        Logger.info("#{conn.method} #{conn.request_path}",
          request_id: Logger.metadata()[:request_id],
          duration: duration_us
        )

        Logger.info("Sent #{conn.status} in #{duration_us}µs",
          request_id: Logger.metadata()[:request_id]
        )

        conn
      end)
    else
      conn
    end
  end

  defp should_log?(%Plug.Conn{request_path: path}) do
    path not in @health_check_paths
  end
end
