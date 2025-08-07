defmodule WandererNotifierWeb.StatusController do
  use WandererNotifierWeb, :controller

  alias WandererNotifier.Api.Controllers.SystemInfo

  def show(conn, _params) do
    status = SystemInfo.collect_extended_status()
    json(conn, status)
  end
end
