defmodule WandererNotifier.Web.Router do
  @moduledoc """
  Web router for the WandererNotifier dashboard.
  """
  use Plug.Router
  import Plug.Conn

  alias WandererNotifier.Api.Controllers.HealthController

  # Disable HTTP request/response logging 
  # plug(Plug.Logger, log: :debug)

  # Serve static assets with specific paths first
  plug(Plug.Static,
    at: "/assets",
    from: {:wanderer_notifier, "priv/static/app/assets"},
    headers: %{
      "access-control-allow-origin" => "*",
      "cache-control" => "public, max-age=0"
    }
  )

  # Serve specific static files
  plug(Plug.Static,
    at: "/",
    from: :wanderer_notifier,
    only: ~w(favicon.ico robots.txt)
  )

  # Parse request body for JSON API endpoints
  plug(Plug.Parsers,
    parsers: [:json],
    pass: ["application/json"],
    json_decoder: Jason
  )

  # Enable routing
  plug(:match)
  plug(:dispatch)

  # Health check endpoints
  forward("/health", to: HealthController)
  forward("/api/health", to: HealthController)

  # 404 handler
  match _ do
    send_resp(conn, 404, "Not found")
  end
end
