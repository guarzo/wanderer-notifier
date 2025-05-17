defmodule WandererNotifier.Api.Controllers.HealthControllerTest do
  use ExUnit.Case, async: true
  import Plug.Test

  alias WandererNotifier.Web.Router

  @opts Router.init([])

  describe "GET /api/health" do
    test "returns 200 and status OK" do
      conn = conn(:get, "/api/health") |> Router.call(@opts)
      assert conn.status == 200
      assert %{"status" => "OK"} = Jason.decode!(conn.resp_body)
    end
  end

  describe "HEAD /api/health" do
    test "returns 200 (no body for HEAD)" do
      conn = conn(:head, "/api/health") |> Router.call(@opts)
      assert conn.status == 200
      # HEAD responses have no body
    end
  end

  describe "GET /api/health/unknown" do
    test "returns 404 for unknown route" do
      conn = conn(:get, "/api/health/unknown") |> Router.call(@opts)
      assert conn.status == 404
    end
  end
end
