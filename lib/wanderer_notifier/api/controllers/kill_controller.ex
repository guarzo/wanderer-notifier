defmodule WandererNotifier.Api.Controllers.KillController do
  @moduledoc """
  Controller for kill-related endpoints.
  """
  use Plug.Router
  import Plug.Conn

  alias WandererNotifier.Logger.Logger, as: AppLogger
  alias WandererNotifier.Processing.Killmail.{Cache, Processor}

  plug(Plug.Parsers,
    parsers: [:json],
    pass: ["application/json"],
    json_decoder: Jason
  )

  plug(:match)
  plug(:dispatch)

  # Get recent kills
  get "/recent" do
    case get_recent_kills() do
      {:ok, kills} -> send_json_response(conn, 200, kills)
      {:error, reason} -> send_json_response(conn, 500, %{error: reason})
    end
  end

  # Get kill details
  get "/kill/:kill_id" do
    case Cache.get_kill(kill_id) do
      {:ok, kill} -> send_json_response(conn, 200, kill)
      {:error, :not_cached} -> send_json_response(conn, 404, %{error: "Kill not found in cache"})
      {:error, :not_found} -> send_json_response(conn, 404, %{error: "Kill not found"})
      {:error, reason} -> send_json_response(conn, 500, %{error: reason})
    end
  end

  match _ do
    send_json_response(conn, 404, %{error: "Not found"})
  end

  defp get_recent_kills do
    {:ok, Processor.get_recent_kills()}
  rescue
    error ->
      AppLogger.api_error("Error getting recent kills", %{
        error: inspect(error),
        stacktrace: Exception.format_stacktrace(__STACKTRACE__)
      })

      {:error, "Internal server error"}
  end

  defp send_json_response(conn, status, body) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(body))
  end
end
