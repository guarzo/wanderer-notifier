defmodule WandererNotifier.Api.Controllers.NotificationControllerTest do
  use ExUnit.Case, async: true
  import Plug.Test
  import Plug.Conn

  alias WandererNotifier.Web.Router

  @opts Router.init([])

  describe "GET /api/notifications/settings" do
    test "returns 200 and settings payload" do
      conn = conn(:get, "/api/notifications/settings") |> Router.call(@opts)
      assert conn.status == 200
      body = Jason.decode!(conn.resp_body)
      assert Map.has_key?(body, "channels")
      assert Map.has_key?(body, "features")
      assert Map.has_key?(body, "limits")
    end
  end

  describe "POST /api/notifications/test" do
    test "returns 200 for valid type 'kill'" do
      conn =
        conn(:post, "/api/notifications/test", Jason.encode!(%{"type" => "kill"}))
        |> put_req_header("content-type", "application/json")
        |> Router.call(@opts)

      assert conn.status == 200
      body = Jason.decode!(conn.resp_body)
      assert body["message"] =~ "Test notification sent"
    end

    test "returns 400 for invalid type" do
      conn =
        conn(:post, "/api/notifications/test", Jason.encode!(%{"type" => "invalid"}))
        |> put_req_header("content-type", "application/json")
        |> Router.call(@opts)

      assert conn.status == 400
      body = Jason.decode!(conn.resp_body)
      assert body["error"] =~ "Invalid notification type"
    end
  end

  describe "GET /api/notifications/unknown" do
    test "returns 404 for unknown route" do
      conn = conn(:get, "/api/notifications/unknown") |> Router.call(@opts)
      assert conn.status == 404
    end
  end
end
