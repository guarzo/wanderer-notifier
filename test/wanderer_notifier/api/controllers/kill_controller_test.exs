defmodule WandererNotifier.Api.Controllers.KillControllerTest do
  use ExUnit.Case, async: true
  import Plug.Test

  alias WandererNotifier.Web.Router
  alias WandererNotifier.Killmail.Killmail
  alias WandererNotifier.Api.Controllers.KillController

  @opts Router.init([])
  @controller_opts KillController.init([])
  @mock_kill_id "12345678"
  @unknown_kill_id "999999999"
  @mock_zkb [hash: "hash123", totalValue: 1_000_000.0]
  @mock_esi_data [killmail_time: "2023-06-15T12:34:56Z", solar_system_id: 30_000_142]

  setup do
    # Configure the application to use our mock cache module
    Application.put_env(
      :wanderer_notifier,
      :killmail_cache_module,
      WandererNotifier.Test.Support.Mocks
    )

    # Setup mock data in the cache
    mock_kill = Killmail.new(@mock_kill_id, @mock_zkb, @mock_esi_data)

    # Clear any existing cache data
    Process.put({:cache, "zkill:recent_kills"}, [])
    Process.delete({:cache, "zkill:recent_kills:#{@mock_kill_id}"})
    Process.delete({:cache, "zkill:recent_kills:#{@unknown_kill_id}"})

    # Add our test kill to the cache
    Process.put({:cache, "zkill:recent_kills"}, [@mock_kill_id])
    Process.put({:cache, "zkill:recent_kills:#{@mock_kill_id}"}, mock_kill)

    :ok
  end

  describe "Testing controller directly" do
    test "GET /kill/:kill_id returns kill details when found in cache" do
      # Test the controller directly
      conn =
        conn(:get, "/kill/#{@mock_kill_id}")
        |> KillController.call(@controller_opts)

      # Assert: Check for JSON response with successful status
      assert conn.status == 200
      response = Jason.decode!(conn.resp_body)
      # The controller returns the kill object directly, no data wrapper
      assert is_map(response)
      assert response["killmail_id"] == @mock_kill_id
    end

    test "GET /kill/:kill_id returns 404 for unknown killmail" do
      # Test the controller directly
      conn =
        conn(:get, "/kill/#{@unknown_kill_id}")
        |> KillController.call(@controller_opts)

      # Assert: Check for JSON error response
      assert conn.status == 404
      response = Jason.decode!(conn.resp_body)
      assert Map.has_key?(response, "error")
      assert response["error"] in ["Kill not found", "Kill not found in cache"]
    end

    test "GET /kills returns list of latest killmails" do
      # Test the controller directly
      conn =
        conn(:get, "/kills")
        |> KillController.call(@controller_opts)

      # Assert: Check for JSON response with successful status
      assert conn.status == 200
      response = Jason.decode!(conn.resp_body)
      # The controller returns the kills list directly
      assert is_list(response)
    end
  end

  describe "Testing through router" do
    test "returns kill details when found in cache" do
      # Act: Make the request through the router
      conn = conn(:get, "/api/kill/kill/#{@mock_kill_id}") |> Router.call(@opts)

      # Assert: Check for JSON response with successful status
      assert conn.status == 200
      response = Jason.decode!(conn.resp_body)
      # The controller returns the kill object directly, no data wrapper
      assert is_map(response)
      assert response["killmail_id"] == @mock_kill_id
    end

    test "returns 404 for unknown killmail" do
      # Act: Make the request with a kill ID that doesn't exist
      conn = conn(:get, "/api/kill/kill/#{@unknown_kill_id}") |> Router.call(@opts)

      # Assert: Check for JSON error response
      assert conn.status == 404
      response = Jason.decode!(conn.resp_body)
      assert Map.has_key?(response, "error")

      # The controller will return either "Kill not found" or "Kill not found in cache"
      # depending on the implementation, so accept either
      assert response["error"] in ["Kill not found", "Kill not found in cache"]
    end

    test "returns list of latest killmails" do
      # Act: Make the request
      conn = conn(:get, "/api/kill/kills") |> Router.call(@opts)

      # Assert: Check for JSON response with successful status
      assert conn.status == 200
      response = Jason.decode!(conn.resp_body)
      # The controller returns the kills list directly
      assert is_list(response)
    end

    test "returns 404 for unknown routes" do
      # Act: Make the request to a non-existent endpoint
      conn = conn(:get, "/api/kill/unknown_endpoint") |> Router.call(@opts)

      # Assert: Check for JSON error response
      assert conn.status == 404
      response = Jason.decode!(conn.resp_body)
      assert Map.has_key?(response, "error")
      assert response["error"] == "not_found"
    end
  end
end
