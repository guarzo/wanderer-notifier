defmodule WandererNotifier.Api.Controllers.HealthController do
  @moduledoc """
  Controller for health check endpoints.
  """
  use WandererNotifier.Api.Controller

  # Health check endpoint
  get "/" do
    send_success(conn, %{status: "OK"})
  end

  # Support HEAD requests for health checks
  head "/" do
    send_success(conn, %{status: "OK"})
  end
end
