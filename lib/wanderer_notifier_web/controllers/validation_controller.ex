defmodule WandererNotifierWeb.ValidationController do
  @moduledoc """
  Controller for validation API endpoints.

  Provides simple endpoints to enable/disable validation modes
  for testing killmail notifications in production.
  """

  use WandererNotifierWeb, :controller
  require Logger

  alias WandererNotifier.Shared.Utils.ValidationManager, as: Manager

  @doc """
  Enable system validation mode.
  Next killmail will be processed as a system notification.
  """
  def enable_system(conn, _params) do
    result = Manager.enable_system_validation()

    success_message =
      "System validation enabled. Next killmail will be processed as system notification."

    handle_manager_response(conn, result, success_message)
  end

  @doc """
  Enable character validation mode.
  Next killmail will be processed as a character notification.
  """
  def enable_character(conn, _params) do
    result = Manager.enable_character_validation()

    success_message =
      "Character validation enabled. Next killmail will be processed as character notification."

    handle_manager_response(conn, result, success_message)
  end

  # Private helper function to handle Manager responses consistently
  defp handle_manager_response(conn, result, success_message) do
    case result do
      {:ok, state} ->
        Logger.info("#{success_message} via API")

        response = %{
          success: true,
          message: success_message,
          mode: state.mode
        }

        # Include expires_at if present
        response =
          if Map.has_key?(state, :expires_at) do
            Map.put(response, :expires_at, state.expires_at)
          else
            response
          end

        conn
        |> put_status(:ok)
        |> json(response)

      {:error, _reason} ->
        conn
        |> put_status(:internal_server_error)
        |> json(%{success: false, error: "Internal server error"})
    end
  end

  @doc """
  Disable validation mode.
  """
  def disable(conn, _params) do
    case Manager.disable_validation() do
      {:ok, _state} ->
        Logger.info("Validation disabled via API")

        conn
        |> put_status(:ok)
        |> json(%{
          success: true,
          message: "Validation mode disabled."
        })

      {:error, reason} ->
        conn
        |> put_status(:internal_server_error)
        |> json(%{success: false, error: inspect(reason)})
    end
  end

  @doc """
  Get current validation status.
  """
  def status(conn, _params) do
    status = Manager.get_status()

    conn
    |> put_status(:ok)
    |> json(%{
      success: true,
      status: status
    })
  end
end
