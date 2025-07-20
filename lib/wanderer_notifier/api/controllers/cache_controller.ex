defmodule WandererNotifier.Api.Controllers.CacheController do
  @moduledoc """
  Cache analytics API controller.

  NOTE: This controller is temporarily disabled as the Analytics and Insights
  modules have been removed in the cache simplification effort.
  These features may be re-implemented in a simpler form in the future.
  """

  use Plug.Router
  require Logger

  # Enable request parsing
  plug(Plug.Parsers,
    parsers: [:json],
    pass: ["application/json"],
    json_decoder: Jason
  )

  # Enable routing
  plug(:match)
  plug(:dispatch)

  # CORS headers
  plug(:add_cors_headers)

  # All cache analytics endpoints are temporarily disabled
  match _ do
    send_json_response(conn, 501, %{
      error: "Cache analytics temporarily unavailable",
      message:
        "Cache analytics and insights features are being redesigned as part of the infrastructure simplification effort"
    })
  end

  # Helper functions

  defp add_cors_headers(conn, _opts) do
    conn
    |> put_resp_header("access-control-allow-origin", "*")
    |> put_resp_header("access-control-allow-methods", "GET, POST, PUT, DELETE, OPTIONS")
    |> put_resp_header("access-control-allow-headers", "Content-Type, Authorization")
    |> put_resp_header("access-control-max-age", "86400")
  end

  defp send_json_response(conn, status, data) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(data))
  end
end
