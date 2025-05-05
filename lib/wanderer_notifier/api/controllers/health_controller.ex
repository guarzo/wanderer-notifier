defmodule WandererNotifier.Api.Controllers.HealthController do
  @moduledoc """
  Controller for health check endpoints.
  """
  use WandererNotifier.Api.ApiPipeline
  import WandererNotifier.Api.Helpers

  # Health check endpoint
  get "/" do
    send_success(conn, %{status: "OK"})
  end

  # Support HEAD requests for health checks
  head "/" do
    send_success(conn, %{status: "OK"})
  end

  match _ do
    send_error(conn, 404, "not_found")
  end
end
