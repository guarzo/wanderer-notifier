defmodule WandererNotifier.Web.Router do
  @moduledoc """
  Web router for the WandererNotifier dashboard.
  """
  use Plug.Router
  import Plug.Conn

  alias WandererNotifier.Api.Controllers.{
    HealthController,
    KillController,
    NotificationController,
    WebController
  }

  # Basic request logging
  plug(Plug.Logger)

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

  # Health check endpoint
  forward("/health", to: HealthController)

  # API Routes
  forward("/api/health", to: HealthController)
  forward("/api/notifications", to: NotificationController)
  forward("/api/debug", to: WebController)

  # Add kill routes
  forward("/api/kill", to: KillController)

  # Return 404 for /api/web/schedulers
  get "/api/web/schedulers" do
    send_resp(conn, 404, "Not found")
  end

  # React app routes
  get "/schedulers" do
    send_file(conn, 200, "priv/static/app/index.html")
  end

  get "/charts" do
    send_file(conn, 200, "priv/static/app/index.html")
  end

  get "/kill-comparison" do
    send_file(conn, 200, "priv/static/app/index.html")
  end

  # Catch-all route for SPA
  get "/*path" do
    send_file(conn, 200, "priv/static/app/index.html")
  end

  # 404 handler
  match _ do
    send_resp(conn, 404, "Not found")
  end
end
