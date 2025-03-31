defmodule WandererNotifier.Web.Controllers.DebugController do
  @moduledoc """
  Controller for debug endpoints.
  Provides debugging information and tools.
  """

  use Plug.Router
  import Plug.Conn
  alias WandererNotifier.Config.Debug
  alias WandererNotifier.Config.Features
  alias WandererNotifier.Core.{License, Stats}
  alias WandererNotifier.Logger, as: AppLogger

  # This controller handles debug endpoints

  # Enables basic plug functionality
  plug(:match)
  plug(:dispatch)

  # GET /debug
  get "/" do
    # Get current debugging state
    current_state = Debug.config().logging_enabled
    debug_enabled = current_state == true

    conn
    |> put_resp_content_type("text/html")
    |> send_resp(200, debug_page_html(debug_enabled))
  end

  # POST /debug/toggle - Toggle debug logging
  post "/toggle" do
    # Get current state and toggle it
    current_state = Debug.debug_logging_enabled?()
    new_state = !current_state

    # Apply the new state
    Debug.set_debug_logging(new_state)

    # Log the change
    AppLogger.api_info("Debug logging #{if new_state, do: "enabled", else: "disabled"}")

    # Redirect back to debug page using conn manipulation directly
    conn
    |> put_resp_header("location", "/debug")
    |> send_resp(302, "Redirecting...")
  end

  # Helper to generate debug page HTML
  defp debug_page_html(debug_enabled) do
    """
    <!DOCTYPE html>
    <html>
      <head>
        <title>Wanderer Notifier Debug</title>
        <style>
          body {
            font-family: Arial, sans-serif;
            max-width: 800px;
            margin: 0 auto;
            padding: 20px;
          }
          h1 {
            color: #333;
          }
          .status {
            font-weight: bold;
            color: #{if debug_enabled, do: "green", else: "red"};
          }
          button {
            padding: 8px 16px;
            margin: 10px 0;
            cursor: pointer;
          }
          pre {
            background-color: #f4f4f4;
            padding: 10px;
            border-radius: 4px;
            overflow-x: auto;
          }
        </style>
      </head>
      <body>
        <h1>Wanderer Notifier Debug Panel</h1>
        <p>Debug logging is currently <span class="status">#{if debug_enabled, do: "ENABLED", else: "DISABLED"}</span></p>
        <form method="post" action="/debug/toggle">
          <button type="submit">#{if debug_enabled, do: "Disable", else: "Enable"} Debug Logging</button>
        </form>

        <h2>System Information</h2>
        <pre>#{Jason.encode!(system_info(), pretty: true)}</pre>
      </body>
    </html>
    """
  end

  # Get system information for debugging
  defp system_info do
    %{
      version: "1.0.0",
      features: Features.get_feature_status(),
      license: License.status(),
      stats: Stats.get_stats(),
      debug_enabled: Debug.config().logging_enabled
    }
  end

  # Match all other routes
  match _ do
    send_resp(conn, 404, "Not found")
  end

  def status(conn, _params) do
    debug_config = Debug.config()

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(
      200,
      Jason.encode!(%{
        success: true,
        debug_enabled: debug_config.logging_enabled,
        map_debug: debug_config.map_settings
      })
    )
  end
end
