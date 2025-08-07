defmodule WandererNotifierWeb.FallbackController do
  use WandererNotifierWeb, :controller

  def not_found(conn, _params) do
    conn
    |> put_status(:not_found)
    |> json(%{error: "Not found"})
  end
end
