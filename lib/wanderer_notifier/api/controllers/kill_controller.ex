defmodule WandererNotifier.Api.Controllers.KillController do
  @moduledoc """
  Controller for kill-related endpoints.
  """
  use WandererNotifier.Api.Controller
  alias WandererNotifier.Processing.Killmail.{Cache, Processor}
  alias WandererNotifier.Logger.Logger, as: AppLogger

  # Get recent kills
  get "/recent" do
    case get_recent_kills(conn) do
      {:ok, kills} -> send_success(conn, kills)
      {:error, reason} -> send_error(conn, 500, reason)
    end
  end

  # Get kill details
  get "/kill/:kill_id" do
    case Cache.get_kill(kill_id) do
      {:ok, kill} -> send_success(conn, kill)
      {:error, :not_cached} -> send_error(conn, 404, "Kill not found in cache")
      {:error, :not_found} -> send_error(conn, 404, "Kill not found")
      {:error, reason} -> send_error(conn, 500, reason)
    end
  end

  match _ do
    send_error(conn, 404, "Not found")
  end

  defp get_recent_kills(conn) do
    {:ok, Processor.get_recent_kills()}
  rescue
    error ->
      AppLogger.api_error("Error getting recent kills", %{
        error: inspect(error),
        stacktrace: Exception.format_stacktrace(__STACKTRACE__)
      })

      send_error(conn, 500, "An unexpected error occurred")
  end
end
