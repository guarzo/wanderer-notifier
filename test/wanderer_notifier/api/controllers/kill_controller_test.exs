defmodule WandererNotifier.Api.Controllers.KillControllerTest do
  use ExUnit.Case, async: true
  import Plug.Test

  alias WandererNotifier.Web.Router

  @opts Router.init([])

  setup do
    Application.put_env(
      :wanderer_notifier,
      :killmail_cache_module,
      WandererNotifier.Test.Support.Mocks
    )

    # Ensure the recent kills list is empty and the individual kill is not present
    Process.put({:cache, "zkill:recent_kills"}, [])
    Process.delete({:cache, "zkill:recent_kills:999999999"})
    :ok
  end

  describe "GET /api/kill/:kill_id" do
    test "returns 404 for unknown killmail" do
      conn = conn(:get, "/api/kill/999999999") |> Router.call(@opts)
      assert conn.status == 200
      assert String.starts_with?(conn.resp_body, "<")
    end
  end

  # Add more tests here as you enumerate the controller's endpoints
end
