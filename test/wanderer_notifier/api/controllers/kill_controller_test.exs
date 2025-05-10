defmodule WandererNotifier.Api.Controllers.KillControllerTest do
  use ExUnit.Case, async: false
  import Mox

  alias WandererNotifier.Killmail.Cache
  alias WandererNotifier.Killmail.Processor
  alias WandererNotifier.Killmail.Killmail

  # Make mocks verifiable
  setup :verify_on_exit!

  setup do
    # Sample test data
    test_kill = %Killmail{
      killmail_id: "12345",
      victim_name: "Test Victim",
      victim_corporation: "Test Corp",
      victim_corp_ticker: "TEST",
      ship_name: "Test Ship",
      system_name: "Test System",
      zkb: %{
        "totalValue" => 1_000_000,
        "points" => 10,
        "hash" => "abc123"
      }
    }

    test_recent_kills = [
      %Killmail{
        killmail_id: "12345",
        victim_name: "Test Victim 1",
        system_name: "Test System 1"
      },
      %Killmail{
        killmail_id: "12346",
        victim_name: "Test Victim 2",
        system_name: "Test System 2"
      }
    ]

    # Create cache and processor mocks
    cache_module = MockCache
    processor_module = MockProcessor

    # Define mock behaviors
    defmodule MockCache do
      def get_kill("12345") do
        test_kill = %Killmail{
          killmail_id: "12345",
          victim_name: "Test Victim",
          victim_corporation: "Test Corp",
          victim_corp_ticker: "TEST",
          ship_name: "Test Ship",
          system_name: "Test System",
          zkb: %{
            "totalValue" => 1_000_000,
            "points" => 10,
            "hash" => "abc123"
          }
        }

        {:ok, test_kill}
      end

      def get_kill("not_found") do
        {:error, :not_found}
      end

      def get_kill("not_cached") do
        {:error, :not_cached}
      end

      def get_kill("error") do
        {:error, "Test error"}
      end

      def get_kill(_) do
        {:ok, nil}
      end

      def get_latest_killmails do
        [
          %Killmail{
            killmail_id: "12345",
            victim_name: "Test Victim 1",
            system_name: "Test System 1"
          },
          %Killmail{
            killmail_id: "12346",
            victim_name: "Test Victim 2",
            system_name: "Test System 2"
          }
        ]
      end
    end

    defmodule MockProcessor do
      def get_recent_kills do
        [
          %Killmail{
            killmail_id: "12345",
            victim_name: "Test Victim 1",
            system_name: "Test System 1"
          },
          %Killmail{
            killmail_id: "12346",
            victim_name: "Test Victim 2",
            system_name: "Test System 2"
          }
        ]
      end
    end

    # Set up logger module with a module that doesn't perform actual logging
    defmodule NoopLogger do
      def debug(_msg, _meta \\ []), do: :ok
      def info(_msg, _meta \\ []), do: :ok
      def warn(_msg, _meta \\ []), do: :ok
      def error(_msg, _meta \\ []), do: :ok
      def api_debug(_msg, _meta \\ []), do: :ok
      def api_info(_msg, _meta \\ []), do: :ok
      def api_warn(_msg, _meta \\ []), do: :ok
      def api_error(_msg, _meta \\ []), do: :ok
    end

    # Set up application env
    Application.put_env(:wanderer_notifier, :killmail_cache_module, MockCache)
    Application.put_env(:wanderer_notifier, :logger_module, NoopLogger)

    # Clean up on test exit
    on_exit(fn ->
      Application.delete_env(:wanderer_notifier, :killmail_cache_module)
      Application.delete_env(:wanderer_notifier, :logger_module)
    end)

    # Return test data
    {:ok, %{kill: test_kill, recent_kills: test_recent_kills}}
  end

  # Helper function to simulate a request to the controller
  defp request(method, path, params \\ %{}) do
    # Create a fake connection
    conn = %{
      method: method,
      request_path: path,
      params: params,
      private: %{},
      resp_headers: [],
      status: nil,
      resp_body: nil
    }

    # Import controller module
    controller = WandererNotifier.Api.Controllers.KillController

    # Run the controller action based on the path
    cond do
      method == "GET" && path == "/recent" ->
        apply(controller, :do_match, [conn, []])

      method == "GET" && String.match?(path, ~r/^\/kill\/\d+$/) ->
        kill_id = String.replace(path, "/kill/", "")
        conn = Map.put(conn, :params, Map.put(params, "kill_id", kill_id))
        apply(controller, :do_match, [conn, []])

      method == "GET" && path == "/kills" ->
        apply(controller, :do_match, [conn, []])

      true ->
        # Default match
        apply(controller, :do_match, [conn, []])
    end
  end

  # Helper function to extract JSON response
  defp parse_json_response(conn) do
    Jason.decode!(conn.resp_body)
  end

  describe "GET /recent" do
    test "returns recent kills successfully" do
      # Make request
      conn = request("GET", "/recent")

      # Verify response
      assert conn.status == 200
      response = parse_json_response(conn)
      assert response["status"] == "success"
      assert is_list(response["data"])
      assert length(response["data"]) == 2
      assert Enum.at(response["data"], 0)["killmail_id"] == "12345"
      assert Enum.at(response["data"], 1)["killmail_id"] == "12346"
    end

    test "handles error when getting recent kills" do
      # Override the get_recent_kills function to raise an error
      original_module = Application.get_env(:wanderer_notifier, :killmail_cache_module)

      defmodule ErrorMockProcessor do
        def get_recent_kills do
          raise "Test error"
        end
      end

      # Replace the module temporarily
      Application.put_env(:wanderer_notifier, :processor_module, ErrorMockProcessor)

      # Make request - this should be handled gracefully
      conn = request("GET", "/recent")

      # Restore the original module
      Application.put_env(:wanderer_notifier, :processor_module, original_module)

      # Verify response
      assert conn.status == 500
      response = parse_json_response(conn)
      assert response["status"] == "error"
      assert response["message"] == "An unexpected error occurred"
    end
  end

  describe "GET /kill/:kill_id" do
    test "returns kill details successfully" do
      # Make request
      conn = request("GET", "/kill/12345")

      # Verify response
      assert conn.status == 200
      response = parse_json_response(conn)
      assert response["status"] == "success"
      assert response["data"]["killmail_id"] == "12345"
      assert response["data"]["victim_name"] == "Test Victim"
      assert response["data"]["victim_corporation"] == "Test Corp"
    end

    test "returns 404 when kill is nil" do
      # Make request
      conn = request("GET", "/kill/99999")

      # Verify response
      assert conn.status == 404
      response = parse_json_response(conn)
      assert response["status"] == "error"
      assert response["message"] == "Kill not found"
    end

    test "returns 404 when kill is not found" do
      # Make request
      conn = request("GET", "/kill/not_found")

      # Verify response
      assert conn.status == 404
      response = parse_json_response(conn)
      assert response["status"] == "error"
      assert response["message"] == "Kill not found"
    end

    test "returns 404 when kill is not cached" do
      # Make request
      conn = request("GET", "/kill/not_cached")

      # Verify response
      assert conn.status == 404
      response = parse_json_response(conn)
      assert response["status"] == "error"
      assert response["message"] == "Kill not found in cache"
    end

    test "returns 500 on other errors" do
      # Make request
      conn = request("GET", "/kill/error")

      # Verify response
      assert conn.status == 500
      response = parse_json_response(conn)
      assert response["status"] == "error"
      assert response["message"] == "Test error"
    end
  end

  describe "GET /kills" do
    test "returns list of kills successfully" do
      # Make request
      conn = request("GET", "/kills")

      # Verify response
      assert conn.status == 200
      response = parse_json_response(conn)
      assert response["status"] == "success"
      assert is_list(response["data"])
      assert length(response["data"]) == 2
      assert Enum.at(response["data"], 0)["killmail_id"] == "12345"
      assert Enum.at(response["data"], 1)["killmail_id"] == "12346"
    end
  end

  describe "Unknown routes" do
    test "returns 404 for unknown routes" do
      # Make request
      conn = request("GET", "/unknown_route")

      # Verify response
      assert conn.status == 404
      response = parse_json_response(conn)
      assert response["status"] == "error"
      assert response["message"] == "not_found"
    end
  end
end
