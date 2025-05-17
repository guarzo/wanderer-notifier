defmodule WandererNotifier.Killmail.KillmailTest do
  use ExUnit.Case, async: true
  alias WandererNotifier.Killmail.Killmail

  describe "new/2" do
    test "creates a valid killmail struct with two arguments" do
      killmail = Killmail.new("12345", %{"totalValue" => 1_000_000})
      assert %Killmail{} = killmail
      assert killmail.killmail_id == "12345"
      assert killmail.zkb == %{"totalValue" => 1_000_000}
      assert killmail.esi_data == nil
    end

    test "creates a valid killmail struct with three arguments" do
      esi_data = %{"solar_system_id" => 30_000_142}
      killmail = Killmail.new("12345", %{"totalValue" => 1_000_000}, esi_data)
      assert %Killmail{} = killmail
      assert killmail.killmail_id == "12345"
      assert killmail.zkb == %{"totalValue" => 1_000_000}
      assert killmail.esi_data == esi_data
    end
  end

  describe "from_map/1" do
    test "creates a killmail struct from a map" do
      map = %{
        "killmail_id" => 123_456_789,
        "zkb" => %{"hash" => "abcd1234", "totalValue" => 1_000_000.0},
        "esi_data" => %{
          "victim" => %{"character_id" => 98_765, "ship_type_id" => 12_345},
          "attackers" => [%{"character_id" => 54_321, "ship_type_id" => 67_890}],
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

  describe "Access behavior" do
    setup do
      esi_data = %{
        "victim" => %{"character_id" => 93_847_759, "ship_type_id" => 33_470},
        "solar_system_id" => 30_000_142,
        "attackers" => [
          %{"character_id" => 95_465_499, "ship_type_id" => 11_987}
        ]
      }

      zkb_data = %{
        "totalValue" => 1_000_000_000,
        "points" => 100
      }

      killmail = Killmail.new("12345", zkb_data, esi_data)

      %{killmail: killmail}
    end

    test "allows direct field access via string keys", %{killmail: killmail} do
      assert killmail["killmail_id"] == "12345"
      assert killmail["zkb"] == %{"totalValue" => 1_000_000_000, "points" => 100}

      assert killmail["esi_data"] == %{
               "victim" => %{"character_id" => 93_847_759, "ship_type_id" => 33_470},
               "solar_system_id" => 30_000_142,
               "attackers" => [
                 %{"character_id" => 95_465_499, "ship_type_id" => 11_987}
               ]
             }
    end

    test "allows access to nested ESI data via string keys", %{killmail: killmail} do
      assert killmail["victim"] == %{"character_id" => 93_847_759, "ship_type_id" => 33_470}
      assert killmail["solar_system_id"] == 30_000_142
      assert killmail["attackers"] == [%{"character_id" => 95_465_499, "ship_type_id" => 11_987}]
    end

    test "returns nil for undefined keys", %{killmail: killmail} do
      assert killmail["undefined_key"] == nil
    end

    test "get_and_update allows modification of fields", %{killmail: killmail} do
      {old_value, updated_killmail} =
        Access.get_and_update(killmail, "killmail_id", fn current ->
          {current, "54321"}
        end)

      assert old_value == "12345"
      assert updated_killmail.killmail_id == "54321"
    end

    test "pop removes a field value", %{killmail: killmail} do
      {victim, updated_killmail} = Access.pop(killmail, "victim")
      assert victim == %{"character_id" => 93_847_759, "ship_type_id" => 33_470}
      assert updated_killmail["victim"] == nil
    end
  end

  describe "helper functions" do
    setup do
      esi_data = %{
        "victim" => %{"character_id" => 93_847_759, "ship_type_id" => 33_470},
        "solar_system_id" => 30_000_142,
        "attackers" => [
          %{"character_id" => 95_465_499, "ship_type_id" => 11_987}
        ]
      }

      zkb_data = %{
        "totalValue" => 1_000_000_000,
        "points" => 100
      }

      killmail = Killmail.new("12345", zkb_data, esi_data)

      %{killmail: killmail}
    end

    test "get_victim returns victim data", %{killmail: killmail} do
      assert Killmail.get_victim(killmail) == %{
               "character_id" => 93_847_759,
               "ship_type_id" => 33_470
             }
    end

    test "get_attacker returns first attacker", %{killmail: killmail} do
      assert Killmail.get_attacker(killmail) == [
               %{
                 "character_id" => 95_465_499,
                 "ship_type_id" => 11_987
               }
             ]
    end

    test "get_system_id returns solar system ID", %{killmail: killmail} do
      assert Killmail.get_system_id(killmail) == 30_000_142
    end

    test "from_map creates killmail from map", %{killmail: killmail} do
      map = %{
        "killmail_id" => killmail.killmail_id,
        "zkb" => killmail.zkb,
        "esi_data" => killmail.esi_data
      }

      recreated = Killmail.from_map(map)

      assert %Killmail{} = recreated
      assert recreated.killmail_id == killmail.killmail_id
      assert recreated.zkb == killmail.zkb
      assert recreated.esi_data == killmail.esi_data
    end
  end
end
