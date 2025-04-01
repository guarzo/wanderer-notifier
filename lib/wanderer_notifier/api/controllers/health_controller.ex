defmodule WandererNotifier.Api.Controllers.HealthController do
  @moduledoc """
  Controller for health check endpoints.
  """
  use WandererNotifier.Api.Controllers.BaseController

  # Health check endpoint
  get "/health" do
    send_success_response(conn, %{status: "OK"})
  end

  match _ do
    send_error_response(conn, 404, "Not found")
  end
end
