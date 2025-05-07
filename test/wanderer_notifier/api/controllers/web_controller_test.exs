defmodule WandererNotifier.Api.Controllers.WebControllerTest do
  use ExUnit.Case, async: true
  import Plug.Test

  alias WandererNotifier.Web.Router

  @opts Router.init([])

  describe "GET /api/debug/status" do
    test "returns 200 and status payload" do
      conn = conn(:get, "/api/debug/status") |> Router.call(@opts)
      assert conn.status == 200
      body = Jason.decode!(conn.resp_body)
      assert is_map(body)
    end
  end

  describe "GET /api/web/schedulers" do
    test "returns 404 for unknown route" do
      conn = conn(:get, "/api/web/schedulers") |> Router.call(@opts)
      assert conn.status == 404
    end
  end

  # Add more tests here as you enumerate the controller's endpoints
end
