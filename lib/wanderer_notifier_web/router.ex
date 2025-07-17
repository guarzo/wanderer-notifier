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

  scope "/api", WandererNotifierWeb do
    pipe_through(:api)

    # Health check endpoint
    get("/health", HealthController, :check)

    # System status endpoint (replaces existing web server functionality)
    get("/status", StatusController, :show)
  end

  # Catch-all route for undefined paths
  match(:*, "/*path", WandererNotifierWeb.FallbackController, :not_found)
end
