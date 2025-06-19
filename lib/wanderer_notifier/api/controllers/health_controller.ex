defmodule WandererNotifier.Api.Controllers.HealthController do
  @moduledoc """
  Controller for health check endpoints.
  """
  use WandererNotifier.Api.ApiPipeline
  use WandererNotifier.Api.Controllers.ControllerHelpers

  alias WandererNotifier.Api.Controllers.SystemInfo

  # Health check endpoint - simple status
  get "/" do
    send_success(conn, %{
      status: "OK",
      timestamp: WandererNotifier.Utils.TimeUtils.log_timestamp(),
      server_version: WandererNotifier.Config.version()
    })
  end

  # Support HEAD requests for health checks
  head "/" do
    send_resp(conn, 200, "")
  end

  # Detailed health check with system information
  get "/details" do
    detailed_status = SystemInfo.collect_detailed_status()
    send_success(conn, detailed_status)
  end

  match _ do
    send_error(conn, 404, "not_found")
  end
end
