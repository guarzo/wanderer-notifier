defmodule WandererNotifier.Api.Controllers.KillController do
  @moduledoc """
  Controller for kill-related endpoints.
  """
  use WandererNotifier.Api.ApiPipeline
  import WandererNotifier.Api.Helpers

  defp cache_module,
    do:
      Application.get_env(
        :wanderer_notifier,
        :killmail_cache_module,
        WandererNotifier.Killmail.Cache
      )

  alias WandererNotifier.Killmail.Processor
  alias WandererNotifier.Logger.Logger, as: AppLogger

  # Get recent kills
  get "/recent" do
    case get_recent_kills() do
      {:ok, kills} -> send_success(conn, kills)
      {:error, reason} -> send_error(conn, 500, reason)
    end
  end

  # Get kill details
  get "/kill/:kill_id" do
    case cache_module().get_kill(kill_id) do
      {:ok, nil} -> send_error(conn, 404, "Kill not found")
      {:ok, kill} -> send_success(conn, kill)
      {:error, :not_cached} -> send_error(conn, 404, "Kill not found in cache")
      {:error, :not_found} -> send_error(conn, 404, "Kill not found")
      {:error, reason} -> send_error(conn, 500, reason)
    end
  end

  # Get killmail list
  get "/kills" do
    kills = cache_module().get_latest_killmails()
    send_success(conn, kills)
  end

  match _ do
    send_error(conn, 404, "not_found")
  end

  # Private functions
  defp get_recent_kills() do
    case Processor.get_recent_kills() do
      {:error, _} = error_tuple -> error_tuple
      result -> {:ok, result}
    end
  rescue
    error ->
      AppLogger.api_error("Error getting recent kills", %{
        error: inspect(error),
        stacktrace: Exception.format_stacktrace(__STACKTRACE__)
      })

      {:error, "An unexpected error occurred"}
  end
end
