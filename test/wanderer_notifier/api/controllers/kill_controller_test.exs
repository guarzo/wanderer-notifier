defmodule WandererNotifier.Api.Controllers.KillControllerTest do
  use ExUnit.Case, async: true
  import Mox
  import Plug.Test

  alias WandererNotifier.Api.Controllers.KillController

  # Set up Mox for this test
  setup :set_mox_from_context
  setup :verify_on_exit!

  @opts KillController.init([])
  @unknown_kill_id 99_999
  @valid_kill_id 12_345
  @valid_kill_data %{
    "killmail_id" => 12_345,
    "killmail_time" => "2023-01-01T12:00:00Z",
    "solar_system_id" => 30_000_142,
    "victim" => %{
      "character_id" => 93_345_033,
      "corporation_id" => 98_553_333,
      "ship_type_id" => 602
    },
    "zkb" => %{"hash" => "hash12345"}
  }

  setup do
    # Set up application environment
    Application.put_env(:wanderer_notifier, :killmail_cache_module, WandererNotifier.MockCache)
    :ok
  end

  describe "GET /kill/:kill_id" do
    test "returns kill details when found in cache" do
      setup_mock_cache(@valid_kill_id, @valid_kill_data)
      assert_kill_response(@valid_kill_id, 200, @valid_kill_data)
    end

    test "returns 404 for unknown killmail" do
      setup_mock_cache(@unknown_kill_id, nil)
      assert_kill_response(@unknown_kill_id, 404, nil)
    end
  end

  describe "Testing through router" do
    test "returns kill details when found in cache" do
      setup_mock_cache(@valid_kill_id, @valid_kill_data)
      assert_kill_response(@valid_kill_id, 200, @valid_kill_data)
    end

    test "returns 404 for unknown killmail" do
      setup_mock_cache(@unknown_kill_id, nil)
      assert_kill_response(@unknown_kill_id, 404, nil)
    end
  end

  # Helper functions
  defp setup_mock_cache(kill_id, kill_data) do
    WandererNotifier.MockCache
    |> expect(:get_kill, fn ^kill_id -> {:ok, kill_data} end)
  end

  defp assert_kill_response(kill_id, expected_status, expected_data) do
    conn =
      :get
      |> conn("/kill/#{kill_id}")
      |> KillController.call(@opts)

    assert conn.status == expected_status

    if expected_data do
      assert Jason.decode!(conn.resp_body)["killmail_id"] == expected_data["killmail_id"]
    end
  end
end
