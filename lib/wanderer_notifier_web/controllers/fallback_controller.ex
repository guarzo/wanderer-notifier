defmodule WandererNotifierWeb.FallbackController do
  @moduledoc """
  Fallback controller for handling undefined routes.
  """

  use Phoenix.Controller, formats: [:json]

  def not_found(conn, _params) do
    conn
    |> put_status(:not_found)
    |> json(%{
      error: "Not Found",
      message: "The requested resource could not be found",
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
    })
  end
end
