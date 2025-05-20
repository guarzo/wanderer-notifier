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

  setup do
    # Set up application environment
    Application.put_env(:wanderer_notifier, :killmail_cache_module, WandererNotifier.MockCache)
    :ok
  end

  describe "GET /kill/:kill_id" do
    test "returns kill details when found in cache" do
      WandererNotifier.MockCache
      |> expect(:get_kill, fn 12_345 ->
        {:ok,
         %{
           "killmail_id" => 12_345,
           "killmail_time" => "2023-01-01T12:00:00Z",
           "solar_system_id" => 30_000_142,
           "victim" => %{
             "character_id" => 93_345_033,
             "corporation_id" => 98_553_333,
             "ship_type_id" => 602
           },
           "zkb" => %{"hash" => "hash12345"}
         }}
      end)

      conn =
        :get
        |> conn("/kill/12345")
        |> KillController.call(@opts)

      assert conn.status == 200
      assert Jason.decode!(conn.resp_body)["killmail_id"] == 12_345
    end

    test "returns 404 for unknown killmail" do
      WandererNotifier.MockCache
      |> expect(:get_kill, fn @unknown_kill_id -> {:ok, nil} end)

      conn =
        :get
        |> conn("/kill/#{@unknown_kill_id}")
        |> KillController.call(@opts)

      assert conn.status == 404
    end
  end

  describe "Testing through router" do
    test "returns kill details when found in cache" do
      WandererNotifier.MockCache
      |> expect(:get_kill, fn 12_345 ->
        {:ok,
         %{
           "killmail_id" => 12_345,
           "killmail_time" => "2023-01-01T12:00:00Z",
           "solar_system_id" => 30_000_142,
           "victim" => %{
             "character_id" => 93_345_033,
             "corporation_id" => 98_553_333,
             "ship_type_id" => 602
           },
           "zkb" => %{"hash" => "hash12345"}
         }}
      end)

      conn =
        :get
        |> conn("/kill/12345")
        |> KillController.call(@opts)

      assert conn.status == 200
      assert Jason.decode!(conn.resp_body)["killmail_id"] == 12_345
    end

    test "returns 404 for unknown killmail" do
      WandererNotifier.MockCache
      |> expect(:get_kill, fn @unknown_kill_id -> {:ok, nil} end)

      conn =
        :get
        |> conn("/kill/#{@unknown_kill_id}")
        |> KillController.call(@opts)

      assert conn.status == 404
    end
  end
end
