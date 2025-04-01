defmodule WandererNotifier.Web.Router do
  @moduledoc """
  Web router for the WandererNotifier dashboard.
  """
  use Plug.Router
  import Plug.Conn
  require Logger

  alias WandererNotifier.Config.Features
  alias WandererNotifier.Logger.Logger, as: AppLogger

  alias WandererNotifier.Api.Controllers.{
    ActivityChartController,
    CharacterController,
    ChartController,
    DebugController,
    HealthController,
    KillController,
    NotificationController
  }

  plug(Plug.Logger)

  # Serve JavaScript and CSS files with correct MIME types
  plug(Plug.Static,
    at: "/assets",
    from: {:wanderer_notifier, "priv/static/app/assets"},
    headers: %{
      "access-control-allow-origin" => "*",
      "cache-control" => "public, max-age=0"
    }
  )

  # Serve static assets directly from app directory without filename restrictions
  plug(Plug.Static,
    at: "/",
    from: {:wanderer_notifier, "priv/static/app"},
    headers: %{
      "access-control-allow-origin" => "*",
      "cache-control" => "public, max-age=0"
    }
  )

  # Serve additional static files
  plug(Plug.Static,
    at: "/",
    from: :wanderer_notifier,
    only: ~w(app images css js favicon.ico robots.txt)
  )

  plug(:match)
  plug(:dispatch)

  # API Routes
  forward("/api/health", to: HealthController)
  forward("/api/characters", to: CharacterController)
  forward("/api/kills", to: KillController)
  forward("/api/notifications", to: NotificationController)
  forward("/api/debug", to: DebugController)
  forward("/api/charts", to: ChartController)
  forward("/api/activity-charts", to: ActivityChartController)

  # React app routes - these need to be before other routes to ensure proper SPA routing

  # Map tools routes
  get "/schedulers" do
    send_file(conn, 200, "priv/static/app/index.html")
  end

  get "/charts" do
    send_file(conn, 200, "priv/static/app/index.html")
  end

  #
  # Catch-all: serve the React index.html from priv/static/app
  #
  match _ do
    send_resp(conn, 404, "Not found")
  end
end
