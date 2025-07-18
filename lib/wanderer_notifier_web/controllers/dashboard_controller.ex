defmodule WandererNotifierWeb.DashboardController do
  @moduledoc """
  Phoenix controller for the web dashboard.
  """
  use WandererNotifierWeb, :controller
  require Logger

  alias WandererNotifier.Api.Controllers.SystemInfo

  def index(conn, _params) do
    # Get the same data as /health/details plus extended stats with error handling
    try do
      detailed_status = SystemInfo.collect_extended_status()
      refresh_interval = Application.get_env(:wanderer_notifier, :dashboard_refresh_interval, 30)

      # Use Phoenix templates for proper HTML rendering
      render(conn, "index.html", %{
        data: detailed_status,
        refresh_interval: refresh_interval
      })
    rescue
      exception ->
        Logger.error("Failed to collect system status: #{inspect(exception)}")

        conn
        |> put_resp_content_type("text/html")
        |> send_resp(
          500,
          "<html><body><h1>Error</h1><p>Unable to collect system status</p></body></html>"
        )
    end
  end
end
