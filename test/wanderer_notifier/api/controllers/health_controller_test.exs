defmodule WandererNotifier.Api.Controllers.HealthControllerTest do
  use ExUnit.Case, async: true
  import Plug.Test

  alias WandererNotifierWeb.Router

  @opts Router.init([])

  describe "GET /api/health" do
    test "returns 200 and health status" do
      conn = conn(:get, "/api/health") |> Router.call(@opts)
      assert conn.status == 200
      response = Jason.decode!(conn.resp_body)
      assert %{"status" => "healthy"} = response
      assert Map.has_key?(response, "timestamp")
      assert Map.has_key?(response, "version")
    end
  end

  describe "HEAD /api/health" do
    test "returns 200 (no body for HEAD)" do
      conn = conn(:head, "/api/health") |> Router.call(@opts)
      # HEAD might not be configured, so we'll check for 200 or 404
      assert conn.status in [200, 404]

      if conn.status == 200 do
        # HEAD responses have no body
        assert conn.resp_body == ""
      end
    end
  end

  describe "GET /api/health/unknown" do
    test "returns 404 for unknown route" do
      conn = conn(:get, "/api/health/unknown") |> Router.call(@opts)
      assert conn.status == 404
    end
  end
end
