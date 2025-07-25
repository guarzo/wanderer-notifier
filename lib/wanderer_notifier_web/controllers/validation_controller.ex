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
    case Manager.enable_system_validation() do
      {:ok, state} ->
        Logger.info("System validation enabled via API")

        conn
        |> put_status(:ok)
        |> json(%{
          success: true,
          message:
            "System validation enabled. Next killmail will be processed as system notification.",
          mode: state.mode,
          expires_at: state.expires_at
        })

      {:error, reason} ->
        conn
        |> put_status(:internal_server_error)
        |> json(%{success: false, error: inspect(reason)})
    end
  end

  @doc """
  Enable character validation mode.
  Next killmail will be processed as a character notification.
  """
  def enable_character(conn, _params) do
    case Manager.enable_character_validation() do
      {:ok, state} ->
        Logger.info("Character validation enabled via API")

        conn
        |> put_status(:ok)
        |> json(%{
          success: true,
          message:
            "Character validation enabled. Next killmail will be processed as character notification.",
          mode: state.mode,
          expires_at: state.expires_at
        })

      {:error, reason} ->
        conn
        |> put_status(:internal_server_error)
        |> json(%{success: false, error: inspect(reason)})
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
