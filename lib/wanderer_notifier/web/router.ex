defmodule WandererNotifier.Web.Router do
  @moduledoc """
  Web router for the WandererNotifier dashboard.
  """
  use Plug.Router
  require Logger

  alias WandererNotifier.Core.Config
  alias WandererNotifier.Web.Controllers.ChartController
  alias WandererNotifier.Web.Controllers.ApiController
  alias WandererNotifier.Web.Controllers.DebugController

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
  plug(Plug.Parsers, parsers: [:json], json_decoder: Jason)
  plug(:dispatch)

  # Forward chart requests to the ChartController
  forward("/charts", to: ChartController)
  
  # Forward debug API requests to the DebugController
  forward("/api/debug", to: DebugController)
  
  # Forward all other API requests to the API controller
  forward("/api", to: ApiController)

  # React app routes - these need to be before other routes to ensure proper SPA routing
  get "/corp-tools" do
    if Config.corp_tools_enabled?() do
      conn
      |> put_resp_header("content-type", "text/html; charset=utf-8")
      |> send_file(200, "priv/static/app/index.html")
    else
      conn
      |> put_resp_content_type("text/html")
      |> send_resp(404, "Corp Tools functionality is not enabled")
    end
  end

  # Map tools routes
  get "/map-tools" do
    if Config.map_tools_enabled?() do
      conn
      |> put_resp_header("content-type", "text/html; charset=utf-8")
      |> send_file(200, "priv/static/app/index.html")
    else
      conn
      |> put_resp_content_type("text/html")
      |> send_resp(404, "Map Tools functionality is not enabled")
    end
  end

  # Handle client-side routing for the React app - Corp Tools
  get "/corp-tools/*path" do
    if Config.corp_tools_enabled?() do
      conn
      |> put_resp_header("content-type", "text/html; charset=utf-8")
      |> send_file(200, "priv/static/app/index.html")
    else
      conn
      |> put_resp_content_type("text/html")
      |> send_resp(404, "Corp Tools functionality is not enabled")
    end
  end

  # Handle client-side routing for the React app - Map Tools
  get "/map-tools/*path" do
    if Config.map_tools_enabled?() do
      conn
      |> put_resp_header("content-type", "text/html; charset=utf-8")
      |> send_file(200, "priv/static/app/index.html")
    else
      conn
      |> put_resp_content_type("text/html")
      |> send_resp(404, "Map Tools functionality is not enabled")
    end
  end

  # Legacy routes for backward compatibility
  get "/charts-dashboard" do
    if Config.corp_tools_enabled?() do
      conn
      |> put_resp_header("location", "/corp-tools")
      |> send_resp(301, "Redirecting to /corp-tools")
    else
      conn
      |> put_resp_content_type("text/html")
      |> send_resp(404, "Corp Tools functionality is not enabled")
    end
  end

  get "/charts-dashboard/*path" do
    if Config.corp_tools_enabled?() do
      conn
      |> put_resp_header("location", "/corp-tools")
      |> send_resp(301, "Redirecting to /corp-tools")
    else
      conn
      |> put_resp_content_type("text/html")
      |> send_resp(404, "Corp Tools functionality is not enabled")
    end
  end

  # Legacy TPS charts page - redirects to the new React dashboard
  get "/tps-charts" do
    if Config.corp_tools_enabled?() do
      conn
      |> put_resp_header("location", "/corp-tools")
      |> send_resp(301, "Redirecting to /corp-tools")
    else
      conn
      |> put_resp_content_type("text/html")
      |> send_resp(404, "Corp Tools functionality is not enabled")
    end
  end

  #
  # HEALTH CHECK ENDPOINT
  #

  get "/health" do
    # Check if critical services are running
    cache_available =
      case Cachex.stats(:wanderer_notifier_cache) do
        {:ok, _stats} -> true
        _ -> false
      end

    # Check if the service GenServer is alive
    service_alive =
      case Process.whereis(WandererNotifier.Services.Service) do
        pid when is_pid(pid) -> Process.alive?(pid)
        _ -> false
      end

    # If critical services are running, return 200 OK
    if cache_available and service_alive do
      conn
      |> put_resp_content_type("application/json")
      |> send_resp(
        200,
        Jason.encode!(%{status: "ok", cache: cache_available, service: service_alive})
      )
    else
      # If any critical service is down, return 503 Service Unavailable
      conn
      |> put_resp_content_type("application/json")
      |> send_resp(
        503,
        Jason.encode!(%{status: "error", cache: cache_available, service: service_alive})
      )
    end
  end

  #
  # API ROUTES (JSON)
  #

  # This endpoint has been moved to ApiController
  # get "/api/test-notification" do

  # This endpoint has been moved to ApiController
  # get "/api/test-character-notification" do

  # This endpoint has been moved to ApiController
  # get "/api/test-system-notification" do

  # This endpoint has been moved to ApiController
  # get "/api/check-characters-endpoint" do

  # This endpoint has been moved to ApiController
  # get "/api/revalidate-license" do

  # This endpoint has been moved to ApiController
  # get "/api/recent-kills" do

  # This endpoint has been moved to ApiController
  # post "/api/test-kill" do

  #
  # Catch-all: serve the React index.html from priv/static/app
  #
  match _ do
    Logger.info("Serving React app for path: #{conn.request_path}")

    index_path = Path.join(:code.priv_dir(:wanderer_notifier), "static/app/index.html")
    Logger.info("Serving index.html from: #{index_path}")

    if File.exists?(index_path) do
      conn
      |> put_resp_header("cache-control", "no-cache")
      |> put_resp_content_type("text/html")
      |> Plug.Conn.send_file(200, index_path)
    else
      Logger.error("Index file not found at: #{index_path}")

      conn
      |> put_resp_content_type("text/plain")
      |> send_resp(404, "Not found: #{conn.request_path}")
    end
  end

  # Note: Helper functions were moved to the ApiController module
end
