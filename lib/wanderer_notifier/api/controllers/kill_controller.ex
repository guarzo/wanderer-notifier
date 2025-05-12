defmodule WandererNotifier.Api.Controllers.KillController do
  @moduledoc """
  Controller for kill-related endpoints.
  """
  use WandererNotifier.Api.ApiPipeline
  import WandererNotifier.Api.Helpers

  # Define a default for compile-time, but we'll use get_env at runtime
  @default_cache_module WandererNotifier.Killmail.Cache

  # Get the cache module at runtime to respect test configurations
  defp cache_module do
    Application.get_env(
      :wanderer_notifier,
      :killmail_cache_module,
      @default_cache_module
    )
  end

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
    # Convert kill_id to integer to ensure key type matches cache keys
    kill_id_int =
      case Integer.parse(kill_id) do
        {id, _} ->
          id

        :error ->
          # If we can't parse it as an integer, we'll still try with the original string
          # but add a debug log since this might indicate an issue
          AppLogger.api_debug("Failed to parse kill_id as integer", %{kill_id: kill_id})
          kill_id
      end

    case cache_module().get_kill(kill_id_int) do
      {:ok, nil} -> send_error(conn, 404, "Kill not found")
      {:ok, kill} -> send_success(conn, kill)
      {:error, :not_cached} -> send_error(conn, 404, "Kill not found in cache")
      {:error, :not_found} -> send_error(conn, 404, "Kill not found")
      {:error, reason} -> send_error(conn, 500, reason)
    end
  end

  # Get killmail list
  get "/kills" do
    case cache_module().get_latest_killmails() do
      {:ok, kills} -> send_success(conn, kills)
      {:error, reason} -> send_error(conn, 500, reason)
      kills when is_list(kills) -> send_success(conn, kills)
    end
  end

  match _ do
    send_error(conn, 404, "not_found")
  end

  # Private functions
  defp get_recent_kills() do
    Processor.get_recent_kills()
  rescue
    # Catch specific known transient errors that can be handled gracefully
    e in HTTPoison.Error ->
      AppLogger.api_error("HTTP error getting recent kills", %{
        error_type: e.__struct__,
        message: Exception.message(e)
      })

      {:error, "Temporary service unavailable"}

    e in Jason.DecodeError ->
      AppLogger.api_error("JSON decode error getting recent kills", %{
        error_type: e.__struct__,
        message: Exception.message(e)
      })

      {:error, "Temporary service unavailable: invalid response format"}

    # Handle general Cachex errors
    e in RuntimeError ->
      message = Exception.message(e)

      if String.contains?(message, ["cachex", "cache"]) do
        AppLogger.api_error("Cache error getting recent kills", %{
          error_type: e.__struct__,
          message: message
        })

        {:error, "Temporary service unavailable: cache error"}
      else
        # Re-raise non-cache related runtime errors
        reraise e, __STACKTRACE__
      end

    # For CaseClauseError and MatchError, check the message content separately
    e in CaseClauseError ->
      message = Exception.message(e)

      if String.contains?(message, ["timeout", "unreachable", "econnrefused", "nxdomain"]) do
        AppLogger.api_error("Network error in case clause getting recent kills", %{
          error_type: e.__struct__,
          message: message
        })

        {:error, "Network error: service temporarily unavailable"}
      else
        # Re-raise non-network related case clause errors
        reraise e, __STACKTRACE__
      end

    e in MatchError ->
      message = Exception.message(e)

      if String.contains?(message, ["timeout", "unreachable", "econnrefused", "nxdomain"]) do
        AppLogger.api_error("Network error in match error getting recent kills", %{
          error_type: e.__struct__,
          message: message
        })

        {:error, "Network error: service temporarily unavailable"}
      else
        # Re-raise non-network related match errors
        reraise e, __STACKTRACE__
      end

    # For unknown errors, log and re-raise to allow proper supervision
    error ->
      AppLogger.api_error("Unexpected error getting recent kills", %{
        error: inspect(error),
        stacktrace: Exception.format(:error, error, __STACKTRACE__)
      })

      reraise error, __STACKTRACE__
  end
end
