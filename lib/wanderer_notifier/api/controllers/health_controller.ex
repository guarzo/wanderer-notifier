defmodule WandererNotifier.Api.Controllers.HealthController do
  @moduledoc """
  Controller for health check endpoints.
  """
  use WandererNotifier.Api.ApiPipeline
  import WandererNotifier.Api.Helpers

  alias WandererNotifier.Web.Server, as: WebServer

  # Health check endpoint - simple status
  get "/" do
    send_success(conn, %{
      status: "OK",
      timestamp: DateTime.utc_now() |> DateTime.to_string(),
      server_version: WandererNotifier.Config.version()
    })
  end

  # Support HEAD requests for health checks
  head "/" do
    send_resp(conn, 200, "")
  end

  # Detailed health check with system information
  get "/details" do
    web_server_status = WebServer.running?()

    # Get memory information
    memory_info = :erlang.memory()

    # Node uptime
    uptime_ms = :erlang.statistics(:wall_clock) |> elem(0)
    uptime_seconds = div(uptime_ms, 1000)

    detailed_status = %{
      status: "OK",
      web_server: %{
        running: web_server_status,
        port: WandererNotifier.Config.port(),
        bind_address: "0.0.0.0"
      },
      system: %{
        uptime_seconds: uptime_seconds,
        memory: %{
          total_kb: div(memory_info[:total], 1024),
          processes_kb: div(memory_info[:processes], 1024),
          system_kb: div(memory_info[:system], 1024)
        },
        scheduler_count: :erlang.system_info(:schedulers_online),
        node_name: Node.self() |> to_string()
      },
      timestamp: DateTime.utc_now() |> DateTime.to_string(),
      server_version: WandererNotifier.Config.version()
    }

    send_success(conn, detailed_status)
  end

  match _ do
    send_error(conn, 404, "not_found")
  end
end
