defmodule WandererNotifier.Web.Router do
  @moduledoc """
  Web router for the WandererNotifier dashboard.
  """
  use Plug.Router

  alias WandererNotifier.Api.Controllers.HealthController
  alias WandererNotifier.Api.Controllers.DashboardController

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

  # Health check endpoints (must come before catch-all routes)
  forward("/health", to: HealthController)
  forward("/api/health", to: HealthController)

  # Dashboard endpoints - both root and /dashboard
  forward("/dashboard", to: DashboardController)
  forward("/", to: DashboardController)
end
