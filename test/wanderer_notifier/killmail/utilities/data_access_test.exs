defmodule WandererNotifier.Killmail.Utilities.DataAccessTest do
  use ExUnit.Case, async: true

  alias WandererNotifier.Killmail.Utilities.DataAccess
  alias WandererNotifier.Killmail.Core.Data, as: KillmailData

  # Define test data
  @killmail_id 12345
  @system_id 30_000_142
  @ship_type_id 587
  @zkb_total_value 1_000_000.0

  # Test killmail data struct
  @test_data %KillmailData{
    killmail_id: @killmail_id,
    solar_system_id: @system_id,
    solar_system_name: "Jita",
    victim_id: 98765,
    victim_name: "Test Victim",
    victim_ship_id: @ship_type_id,
    victim_ship_name: "Test Ship",
    attackers: [
      %{
        "character_id" => 54321,
        "character_name" => "Test Attacker",
        "ship_type_id" => 34562
      }
    ],
    raw_zkb_data: %{
      "totalValue" => @zkb_total_value,
      "points" => 10
    },
    attacker_count: 1
  }

  # Remove tests for these functions that no longer exist:
  # - get_killmail_id/1
  # - get_system_id/1
  # - get_victim_ship_type_id/1
  # - get_zkb_value/1
  # - get_victim_id/1
  # - get_attacker_ids/1
  # - get_characters_involved/1

  describe "debug_info/1" do
    test "extracts debug info from Data" do
      debug_info = DataAccess.debug_info(@test_data)

      assert debug_info.killmail_id == @killmail_id
      assert debug_info.system_id == @system_id
      assert debug_info.system_name == "Jita"
      assert debug_info.victim_id == 98765
      assert debug_info.victim_name == "Test Victim"
      assert debug_info.attacker_count == 1
    end

    test "handles nil attacker_count" do
      killmail = %KillmailData{
        killmail_id: @killmail_id,
        solar_system_id: @system_id,
        solar_system_name: "Jita",
        victim_id: 123,
        victim_name: "Test Victim",
        attacker_count: nil
      }

      debug_info = DataAccess.debug_info(killmail)
      assert debug_info.attacker_count == 0
    end
  end

  describe "find_attacker/2" do
    test "finds attacker by character ID" do
      attacker_data = %{"character_id" => 456, "character_name" => "Test Attacker"}

      killmail = %KillmailData{
        attackers: [
          %{"character_id" => 123},
          attacker_data,
          %{"character_id" => 789}
        ]
      }

      found_attacker = DataAccess.find_attacker(killmail, 456)
      assert found_attacker == attacker_data
    end

    test "handles string character IDs" do
      attacker_data = %{"character_id" => 456, "character_name" => "Test Attacker"}

      killmail = %KillmailData{
        attackers: [
          %{"character_id" => 123},
          attacker_data,
          %{"character_id" => 789}
        ]
      }

      found_attacker = DataAccess.find_attacker(killmail, "456")
      assert found_attacker == attacker_data
    end

    test "returns nil when attacker not found" do
      killmail = %KillmailData{
        attackers: [
          %{"character_id" => 123},
          %{"character_id" => 456}
        ]
      }

      found_attacker = DataAccess.find_attacker(killmail, 789)
      assert found_attacker == nil
    end

    test "returns nil when attackers is nil" do
      killmail = %KillmailData{attackers: nil}
      found_attacker = DataAccess.find_attacker(killmail, 123)
      assert found_attacker == nil
    end
  end

  describe "character_involvement/2" do
    test "identifies character as victim" do
      killmail = %KillmailData{
        victim_id: 123,
        victim_name: "Test Victim",
        victim_ship_id: 456,
        victim_ship_name: "Test Ship"
      }

      result = DataAccess.character_involvement(killmail, 123)

      assert {:victim, victim_data} = result
      assert victim_data["character_id"] == 123
      assert victim_data["character_name"] == "Test Victim"
      assert victim_data["ship_type_id"] == 456
      assert victim_data["ship_type_name"] == "Test Ship"
    end

    test "identifies character as attacker" do
      attacker_data = %{"character_id" => 456, "character_name" => "Test Attacker"}

      killmail = %KillmailData{
        victim_id: 123,
        attackers: [
          attacker_data,
          %{"character_id" => 789}
        ]
      }

      result = DataAccess.character_involvement(killmail, 456)

      assert {:attacker, found_attacker} = result
      assert found_attacker == attacker_data
    end

    test "returns nil when character not involved" do
      killmail = %KillmailData{
        victim_id: 123,
        attackers: [
          %{"character_id" => 456},
          %{"character_id" => 789}
        ]
      }

      result = DataAccess.character_involvement(killmail, 999)
      assert result == nil
    end
  end

  describe "all_character_ids/1" do
    test "returns all character IDs from killmail" do
      killmail = %KillmailData{
        victim_id: 123,
        attackers: [
          %{"character_id" => 456},
          %{"character_id" => 789},
          # Duplicate to test uniqueness
          %{"character_id" => 456}
        ]
      }

      character_ids = DataAccess.all_character_ids(killmail)
      assert Enum.sort(character_ids) == Enum.sort([123, 456, 789])
    end

    test "handles nil victim_id" do
      killmail = %KillmailData{
        victim_id: nil,
        attackers: [
          %{"character_id" => 456},
          %{"character_id" => 789}
        ]
      }

      character_ids = DataAccess.all_character_ids(killmail)
      assert Enum.sort(character_ids) == Enum.sort([456, 789])
    end

    test "handles nil attackers" do
      killmail = %KillmailData{
        victim_id: 123,
        attackers: nil
      }

      character_ids = DataAccess.all_character_ids(killmail)
      assert character_ids == [123]
    end

    test "handles nil character_id in attackers" do
      killmail = %KillmailData{
        victim_id: 123,
        attackers: [
          %{"character_id" => 456},
          %{"character_id" => nil},
          %{"ship_type_id" => 789}
        ]
      }

      character_ids = DataAccess.all_character_ids(killmail)
      assert Enum.sort(character_ids) == Enum.sort([123, 456])
    end
  end

  describe "summary/1" do
    test "generates human-readable summary" do
      killmail = %KillmailData{
        killmail_id: @killmail_id,
        victim_name: "Test Victim",
        victim_ship_name: "Test Ship",
        solar_system_name: "Jita"
      }

      summary = DataAccess.summary(killmail)
      assert summary == "Killmail #12345: Test Victim lost a Test Ship in Jita"
    end

    test "handles missing information with default values" do
      killmail = %KillmailData{
        killmail_id: @killmail_id,
        victim_name: nil,
        victim_ship_name: nil,
        solar_system_name: nil
      }

      summary = DataAccess.summary(killmail)
      assert summary == "Killmail #12345: Unknown lost a Unknown Ship in Unknown System"
    end
  end
end
