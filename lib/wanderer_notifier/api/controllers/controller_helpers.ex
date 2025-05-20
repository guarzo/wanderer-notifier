defmodule WandererNotifier.Api.Controllers.ControllerHelpers do
  @moduledoc """
  Shared controller functionality for API endpoints.
  Provides common helper functions and error handling.
  """

  defmacro __using__(_) do
    quote do
      import Plug.Conn
      import WandererNotifier.Api.Helpers
      # fallback for unmatched routes
      def match(conn), do: send_error(conn, 404, "not_found")
    end
  end

  @doc """
  Sends an error response with the given status code and message.
  """
  def send_error(conn, status, msg) do
    conn
    |> Plug.Conn.put_status(status)
    |> Plug.Conn.put_resp_content_type("application/json")
    |> Plug.Conn.send_resp(status, Jason.encode!(%{error: msg}))
    |> Plug.Conn.halt()
  end
end
