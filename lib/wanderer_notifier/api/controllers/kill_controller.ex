defmodule WandererNotifier.Api.Controllers.KillController do
  @moduledoc """
  Controller for kill-related endpoints.
  """
  use WandererNotifier.Api.Controllers.BaseController
  alias WandererNotifier.Processing.Killmail.{Cache, Processor}

  # Get recent kills
  get "/recent" do
    case get_recent_kills(conn) do
      {:ok, kills} -> send_success_response(conn, kills)
      {:error, reason} -> send_error_response(conn, 500, reason)
    end
  end

  # Get kill details
  get "/kill/:kill_id" do
    case Cache.get_kill(kill_id) do
      {:ok, kill} -> send_success_response(conn, kill)
      {:error, :not_cached} -> send_error_response(conn, 404, "Kill not found in cache")
      {:error, :not_found} -> send_error_response(conn, 404, "Kill not found")
      {:error, reason} -> send_error_response(conn, 500, reason)
    end
  end

  match _ do
    send_error_response(conn, 404, "Not found")
  end

  defp get_recent_kills(conn) do
    {:ok, Processor.get_recent_kills()}
  rescue
    error -> handle_error(conn, error, __MODULE__)
  end
end
