defmodule WandererNotifier.Api.Controllers.KillController do
  @moduledoc """
  Controller for kill-related endpoints.
  """
  use WandererNotifier.Api.ApiPipeline
  import WandererNotifier.Api.Helpers

  # Define a default for compile-time, but we'll use get_env at runtime
  @default_cache_module WandererNotifier.Killmail.Cache

  alias WandererNotifier.Killmail.Processor
  alias WandererNotifier.Logger.Logger, as: AppLogger
  alias Cachex

  # Get the cache module at runtime to respect test configurations
  defp cache_module do
    Application.get_env(
      :wanderer_notifier,
      :killmail_cache_module,
      @default_cache_module
    )
  end

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
    case Integer.parse(kill_id) do
      {id, ""} ->
        case cache_module().get_kill(id) do
          {:ok, kill} when not is_nil(kill) ->
            send_success(conn, kill)

          # Handle all 404 scenarios
          {:ok, nil} ->
            send_error(conn, 404, "Kill not found")

          {:error, :not_cached} ->
            send_error(conn, 404, "Kill not found")

          {:error, :not_found} ->
            send_error(conn, 404, "Kill not found")

          {:error, reason} ->
            send_error(conn, 500, reason)

          _ ->
            # Catch any unexpected response format
            send_error(conn, 500, "Unexpected error retrieving kill data")
        end

      {_, _remainder} ->
        AppLogger.api_debug("Kill ID contains non-numeric characters", %{kill_id: kill_id})
        send_error(conn, 400, "Invalid kill ID format")
        halt(conn)

      :error ->
        # If we can't parse it as an integer, we'll return a 400 error
        AppLogger.api_debug("Failed to parse kill_id as integer", %{kill_id: kill_id})
        send_error(conn, 400, "Invalid kill ID format")
        halt(conn)
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

      {:error, "Temporary service unavailable"}

    e in Cachex.Error ->
      AppLogger.api_error("Cache error getting recent kills", %{
        error_type: e.__struct__,
        message: Exception.message(e)
      })

      {:error, "Temporary service unavailable"}

    # For unknown errors, log and re-raise to let supervisor handle restart
    error ->
      AppLogger.api_error("Unexpected error getting recent kills", %{
        error: inspect(error),
        stacktrace: Exception.format(:error, error, __STACKTRACE__)
      })

      reraise error, __STACKTRACE__
  end
end
