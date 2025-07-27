defmodule WandererNotifierWeb.Router do
  @moduledoc """
  Phoenix router for WandererNotifier with minimal web functionality.

  Provides basic health check endpoints and preserves existing
  web functionality during Phoenix migration.
  """

  use Phoenix.Router

  import Plug.Conn
  import Phoenix.Controller

  pipeline :api do
    plug(:accepts, ["json"])
  end

  pipeline :browser do
    plug(:accepts, ["html"])
    plug(:put_secure_browser_headers)
  end

  # Dashboard route (root)
  scope "/", WandererNotifierWeb do
    pipe_through(:browser)

    get("/", DashboardController, :index)
  end

  scope "/api", WandererNotifierWeb do
    pipe_through(:api)

    # Health check endpoint
    get("/health", HealthController, :check)

    # System status endpoint (replaces existing web server functionality)
    get("/status", StatusController, :show)
  end

  # Validation API endpoints
  scope "/api/validation", WandererNotifierWeb do
    pipe_through(:api)

    post("/enable/system", ValidationController, :enable_system)
    post("/enable/character", ValidationController, :enable_character)
    delete("/disable", ValidationController, :disable)
    get("/status", ValidationController, :status)
  end

  # Catch-all route for undefined paths
  match(:*, "/*path", WandererNotifierWeb.FallbackController, :not_found)
end
