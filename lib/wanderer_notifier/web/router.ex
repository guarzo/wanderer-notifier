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
  get "/map-charts" do
    if Features.map_charts_enabled?() do
      conn
      |> put_resp_header("content-type", "text/html; charset=utf-8")
      |> send_file(200, "priv/static/map-charts/index.html")
    else
      conn
      |> put_resp_content_type("text/plain")
      |> send_resp(404, "Map tools are disabled")
    end
  end

  # Handle client-side routing for the React app - Map Tools
  get "/map-charts/*path" do
    if Features.map_charts_enabled?() do
      conn
      |> put_resp_header("content-type", "text/html; charset=utf-8")
      |> send_file(200, "priv/static/map-charts/index.html")
    else
      conn
      |> put_resp_content_type("text/plain")
      |> send_resp(404, "Map tools are disabled")
    end
  end

  #
  # Catch-all: serve the React index.html from priv/static/app
  #
  match _ do
    AppLogger.api_info("Serving React app", path: conn.request_path)

    index_path = Path.join(:code.priv_dir(:wanderer_notifier), "static/app/index.html")
    AppLogger.api_debug("Serving index.html", path: index_path)

    if File.exists?(index_path) do
      conn
      |> put_resp_header("cache-control", "no-cache")
      |> put_resp_content_type("text/html")
      |> Plug.Conn.send_file(200, index_path)
    else
      AppLogger.api_error("Index file not found", path: index_path)

      conn
      |> put_resp_content_type("text/plain")
      |> send_resp(404, "Not found: #{conn.request_path}")
    end
  end
end
