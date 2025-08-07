defmodule WandererNotifierWeb.HealthController do
  use WandererNotifierWeb, :controller

  def check(conn, _params) do
    json(conn, %{status: "ok", timestamp: DateTime.utc_now()})
  end
end
