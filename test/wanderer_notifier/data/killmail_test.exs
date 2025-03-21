defmodule WandererNotifier.Data.KillmailTest do
  use ExUnit.Case, async: true
  alias WandererNotifier.Data.Killmail

  describe "new/3" do
    test "creates a new killmail struct with required fields" do
      killmail_id = 123_456_789
      zkb = %{"hash" => "abcd1234", "totalValue" => 1_000_000.0}

      result = Killmail.new(killmail_id, zkb)

      assert %Killmail{} = result
      assert result.killmail_id == killmail_id
      assert result.zkb == zkb
      assert result.esi_data == nil
    end

    test "creates a new killmail struct with ESI data" do
      killmail_id = 123_456_789
      zkb = %{"hash" => "abcd1234", "totalValue" => 1_000_000.0}

      esi_data = %{
        "victim" => %{"character_id" => 98765, "ship_type_id" => 12345},
        "attackers" => [%{"character_id" => 54321, "ship_type_id" => 67890}],
        "solar_system_id" => 30_000_142
      }

      result = Killmail.new(killmail_id, zkb, esi_data)

      assert %Killmail{} = result
      assert result.killmail_id == killmail_id
      assert result.zkb == zkb
      assert result.esi_data == esi_data
    end
  end

  describe "from_map/1" do
    test "creates a killmail struct from a map" do
      map = %{
        "killmail_id" => 123_456_789,
        "zkb" => %{"hash" => "abcd1234", "totalValue" => 1_000_000.0},
        "esi_data" => %{
          "victim" => %{"character_id" => 98765, "ship_type_id" => 12345},
          "attackers" => [%{"character_id" => 54321, "ship_type_id" => 67890}],
          "solar_system_id" => 30_000_142
        }
      }

      result = Killmail.from_map(map)

      assert %Killmail{} = result
      assert result.killmail_id == 123_456_789
      assert result.zkb == map["zkb"]
      assert result.esi_data == map["esi_data"]
    end
  end

  describe "Access behaviour" do
    setup do
      killmail =
        Killmail.new(
          123_456_789,
          %{"hash" => "abcd1234", "totalValue" => 1_000_000.0},
          %{
            "victim" => %{"character_id" => 98765, "ship_type_id" => 12345},
            "attackers" => [%{"character_id" => 54321, "ship_type_id" => 67890}],
            "solar_system_id" => 30_000_142
          }
        )

      {:ok, killmail: killmail}
    end

    test "fetch/2 retrieves struct fields", %{killmail: killmail} do
      assert {:ok, 123_456_789} = Access.fetch(killmail, "killmail_id")

      assert {:ok, %{"hash" => "abcd1234", "totalValue" => 1_000_000.0}} =
               Access.fetch(killmail, "zkb")

      assert {:ok, _} = Access.fetch(killmail, "esi_data")
    end

    test "fetch/2 retrieves nested fields from esi_data", %{killmail: killmail} do
      assert {:ok, %{"character_id" => 98765, "ship_type_id" => 12345}} =
               Access.fetch(killmail, "victim")

      assert {:ok, [%{"character_id" => 54321, "ship_type_id" => 67890}]} =
               Access.fetch(killmail, "attackers")

      assert {:ok, 30_000_142} = Access.fetch(killmail, "solar_system_id")
    end

    test "fetch/2 returns error for non-existent keys", %{killmail: killmail} do
      assert :error = Access.fetch(killmail, "non_existent_key")
    end

    test "get/2 retrieves values with default", %{killmail: killmail} do
      assert Killmail.get(killmail, "killmail_id") == 123_456_789
      assert Killmail.get(killmail, "non_existent_key") == nil
      assert Killmail.get(killmail, "non_existent_key", "default") == "default"
    end

    test "get_and_update/3 updates values", %{killmail: killmail} do
      {value, updated} =
        Access.get_and_update(killmail, "killmail_id", fn current -> {current, 987_654_321} end)

      assert value == 123_456_789
      assert updated.killmail_id == 987_654_321

      # Update nested field in esi_data
      {value, updated} =
        Access.get_and_update(killmail, "solar_system_id", fn current -> {current, 30_000_143} end)

      assert value == 30_000_142
      assert updated.esi_data["solar_system_id"] == 30_000_143
    end

    test "pop/2 removes values", %{killmail: killmail} do
      {value, updated} = Access.pop(killmail, "killmail_id")
      assert value == 123_456_789
      assert updated.killmail_id == nil

      # Pop a nested field
      {value, updated} = Access.pop(killmail, "solar_system_id")
      assert value == 30_000_142
      assert updated.esi_data["solar_system_id"] == nil
    end
  end

  describe "helper functions" do
    setup do
      killmail =
        Killmail.new(
          123_456_789,
          %{"hash" => "abcd1234", "totalValue" => 1_000_000.0},
          %{
            "victim" => %{"character_id" => 98765, "ship_type_id" => 12345},
            "attackers" => [
              %{"character_id" => 54321, "ship_type_id" => 67890, "final_blow" => true},
              %{"character_id" => 11111, "ship_type_id" => 22222}
            ],
            "solar_system_id" => 30_000_142
          }
        )

      {:ok, killmail: killmail}
    end

    test "get_victim/1 returns victim data", %{killmail: killmail} do
      victim = Killmail.get_victim(killmail)
      assert victim["character_id"] == 98765
      assert victim["ship_type_id"] == 12345
    end

    test "get_attacker/1 returns first attacker data", %{killmail: killmail} do
      attacker = Killmail.get_attacker(killmail)
      assert attacker["character_id"] == 54321
      assert attacker["ship_type_id"] == 67890
      assert attacker["final_blow"] == true
    end

    test "get_system_id/1 returns solar system ID", %{killmail: killmail} do
      system_id = Killmail.get_system_id(killmail)
      assert system_id == 30_000_142
    end

    test "helper functions return nil when esi_data is nil" do
      killmail = Killmail.new(123_456_789, %{"hash" => "abcd1234"})

      assert Killmail.get_victim(killmail) == nil
      assert Killmail.get_attacker(killmail) == nil
      assert Killmail.get_system_id(killmail) == nil
    end
  end
end
