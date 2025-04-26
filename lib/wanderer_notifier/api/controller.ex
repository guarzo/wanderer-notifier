defmodule WandererNotifier.Api.Controller do
  @moduledoc """
  Shared functionality for all API controllers:
  - JSON parsing plugs
  - Route matching/dispatch
  - Standardized success/error responses
  """

  defmacro __using__(_opts) do
    quote do
      use Plug.Router
      import Plug.Conn

      # --- Common plugs ---
      plug(Plug.Parsers,
        parsers: [:json],
        pass: ["application/json"],
        json_decoder: Jason
      )

      plug(:match)
      plug(:dispatch)

      # --- Standard responses ---
      def send_success(conn, data) do
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(200, Jason.encode!(%{status: "ok", data: data}))
      end

      def send_error(conn, status, message) do
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(status, Jason.encode!(%{error: message}))
      end

      # Fallback for unmatched routes
      match _ do
        send_error(conn, 404, "not_found")
      end
    end
  end
end
