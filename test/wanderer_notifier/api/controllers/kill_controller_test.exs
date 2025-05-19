defmodule WandererNotifier.Api.Controllers.KillControllerTest do
  use ExUnit.Case, async: true
  import Plug.Test
  import Mox

  alias WandererNotifier.Web.Router
  alias WandererNotifier.Api.Controllers.KillController
  alias WandererNotifier.ESI.ServiceMock

  # Define MockCache for the tests
  defmodule MockCache do
    def get(key) do
      cond do
        key == "kill:12345678" ->
          {:ok,
           %{
             "killmail_id" => 12_345_678,
             "zkb" => %{"hash" => "hash123", "totalValue" => 1_000_000.0},
             "solar_system_id" => 30_000_142,
             "killmail_time" => "2023-06-15T12:34:56Z"
           }}

        key == "zkill:recent_kills" ->
          {:ok,
           [
             %{
               "killmail_id" => 12_345_678,
               "zkb" => %{"hash" => "hash123", "totalValue" => 1_000_000.0},
               "solar_system_id" => 30_000_142,
               "killmail_time" => "2023-06-15T12:34:56Z"
             }
           ]}

        true ->
          {:error, :not_found}
      end
    end

    def put(_key, _value), do: {:ok, :mock}
    def put(_key, _value, _ttl), do: {:ok, :mock}
    def delete(_key), do: {:ok, :mock}
    def clear(), do: {:ok, :mock}
    def get_and_update(_key, _fun), do: {:ok, :mock, :mock}
    def set(_key, _value, _opts), do: {:ok, :mock}
    def init_batch_logging(), do: :ok

    def get_recent_kills() do
      {:ok,
       [
         %{
           "killmail_id" => 12_345_678,
           "zkb" => %{"hash" => "hash123", "totalValue" => 1_000_000.0},
           "solar_system_id" => 30_000_142,
           "killmail_time" => "2023-06-15T12:34:56Z"
         }
       ]}
    end

    def get_kill(kill_id) do
      case kill_id do
        12_345_678 ->
          {:ok,
           %{
             "killmail_id" => 12_345_678,
             "zkb" => %{"hash" => "hash123", "totalValue" => 1_000_000.0},
             "solar_system_id" => 30_000_142,
             "killmail_time" => "2023-06-15T12:34:56Z"
           }}

        _ ->
          {:error, :not_found}
      end
    end

    def get_latest_killmails() do
      {:ok,
       [
         %{
           "killmail_id" => 12_345_678,
           "zkb" => %{"hash" => "hash123", "totalValue" => 1_000_000.0},
           "solar_system_id" => 30_000_142,
           "killmail_time" => "2023-06-15T12:34:56Z"
         }
       ]}
    end
  end

  @opts Router.init([])
  @controller_opts KillController.init([])
  @mock_kill_id 12_345_678
  @unknown_kill_id 99_999_999

  # Make sure mocks are verified when the test exits
  setup :verify_on_exit!

  setup do
    # Configure the application to use our mock cache module
    Application.put_env(
      :wanderer_notifier,
      :killmail_cache_module,
      MockCache
    )

    # Set up ESI service mocks
    ServiceMock
    |> stub(:get_killmail, fn kill_id, kill_hash, _opts ->
      case {kill_id, kill_hash} do
        {12_345, "test_hash"} ->
          {:ok,
           %{
             "killmail_id" => 12_345,
             "killmail_time" => "2024-01-01T00:00:00Z",
             "solar_system_id" => 30_000_142,
             "victim" => %{
               "character_id" => 100,
               "corporation_id" => 300,
               "alliance_id" => 400,
               "ship_type_id" => 200
             },
             "attackers" => []
           }}

        _ ->
          {:error, :not_found}
      end
    end)
    |> stub(:get_character_info, fn id, _opts ->
      case id do
        100 -> {:ok, %{"name" => "Test Character"}}
        _ -> {:error, :not_found}
      end
    end)
    |> stub(:get_corporation_info, fn id, _opts ->
      case id do
        300 -> {:ok, %{"name" => "Test Corp", "ticker" => "TEST"}}
        _ -> {:error, :not_found}
      end
    end)
    |> stub(:get_alliance_info, fn id, _opts ->
      case id do
        400 -> {:ok, %{"name" => "Test Alliance", "ticker" => "TEST"}}
        _ -> {:error, :not_found}
      end
    end)
    |> stub(:get_type_info, fn id, _opts ->
      case id do
        200 -> {:ok, %{"name" => "Test Ship"}}
        _ -> {:error, :not_found}
      end
    end)
    |> stub(:get_system, fn id, _opts ->
      case id do
        30_000_142 -> {:ok, %{"name" => "Test System"}}
        _ -> {:error, :not_found}
      end
    end)

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
      assert length(response) > 0
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
      assert length(response) > 0
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
