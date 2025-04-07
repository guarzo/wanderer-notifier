defmodule WandererNotifier.Killmail.ValidationTest do
  use WandererNotifier.DataCase

  alias WandererNotifier.Killmail.Validation
  alias WandererNotifier.Data.Killmail, as: KillmailStruct

  describe "normalize_killmail/1" do
    test "converts a KillmailStruct to normalized map format" do
      # Create a sample killmail struct
      killmail = %KillmailStruct{
        killmail_id: 12345,
        esi_data: %{
          "killmail_time" => "2023-01-01T12:34:56Z",
          "solar_system_id" => 30_000_142,
          "solar_system_name" => "Jita",
          "victim" => %{
            "character_id" => 98765,
            "character_name" => "Victim Pilot",
            "ship_type_id" => 587,
            "ship_type_name" => "Rifter"
          },
          "attackers" => [
            %{
              "character_id" => 11111,
              "character_name" => "Attacker One",
              "ship_type_id" => 24700,
              "ship_type_name" => "Brutix",
              "final_blow" => true,
              "damage_done" => 500
            },
            %{
              "character_id" => 22222,
              "character_name" => "Attacker Two",
              "ship_type_id" => 24702,
              "ship_type_name" => "Ferox",
              "final_blow" => false,
              "damage_done" => 300
            }
          ]
        },
        zkb: %{
          "totalValue" => 15_000_000,
          "points" => 10,
          "npc" => false,
          "solo" => false,
          "hash" => "abc123hash"
        }
      }

      # Call the function under test
      result = Validation.normalize_killmail(killmail)

      # Assert that the result has the expected structure and values
      assert is_map(result)
      assert result.killmail_id == 12345
      assert result.total_value != nil
      assert result.victim_id == 98765
      assert result.victim_name == "Victim Pilot"
      assert result.victim_ship_id == 587
      assert result.victim_ship_name == "Rifter"
      assert result.solar_system_id == 30_000_142
      assert result.solar_system_name == "Jita"
      assert result.final_blow_attacker_id == 11111
      assert result.final_blow_attacker_name == "Attacker One"
      assert result.final_blow_ship_name == "Brutix"
      assert result.attacker_count == 2
      assert result.zkb_hash == "abc123hash"
      assert is_list(result.full_attacker_data)
      assert length(result.full_attacker_data) == 2
    end
  end

  describe "extract_character_involvement/3" do
    test "extracts victim involvement correctly" do
      # Setup killmail with victim data
      killmail = %KillmailStruct{
        esi_data: %{
          "victim" => %{
            "character_id" => 98765,
            "character_name" => "Victim Pilot",
            "ship_type_id" => 587,
            "ship_type_name" => "Rifter"
          }
        }
      }

      # Call the function under test
      result = Validation.extract_character_involvement(killmail, 98765, :victim)

      # Assert expected results
      assert result != nil
      assert result.ship_type_id == 587
      assert result.ship_type_name == "Rifter"
      assert result.damage_done == 0
      assert result.is_final_blow == false
    end

    test "extracts attacker involvement correctly" do
      # Setup killmail with attacker data
      killmail = %KillmailStruct{
        esi_data: %{
          "attackers" => [
            %{
              "character_id" => 11111,
              "character_name" => "Attacker One",
              "ship_type_id" => 24700,
              "ship_type_name" => "Brutix",
              "final_blow" => true,
              "damage_done" => 500,
              "weapon_type_id" => 3001,
              "weapon_type_name" => "Large Blaster"
            },
            %{
              "character_id" => 22222,
              "character_name" => "Attacker Two",
              "ship_type_id" => 24702,
              "ship_type_name" => "Ferox",
              "final_blow" => false,
              "damage_done" => 300
            }
          ]
        }
      }

      # Test extracting the first attacker
      result1 = Validation.extract_character_involvement(killmail, 11111, :attacker)

      # Assert expected results for first attacker
      assert result1 != nil
      assert result1.ship_type_id == 24700
      assert result1.ship_type_name == "Brutix"
      assert result1.damage_done == 500
      assert result1.is_final_blow == true
      assert result1.weapon_type_id == 3001
      assert result1.weapon_type_name == "Large Blaster"

      # Test extracting the second attacker
      result2 = Validation.extract_character_involvement(killmail, 22222, :attacker)

      # Assert expected results for second attacker
      assert result2 != nil
      assert result2.ship_type_id == 24702
      assert result2.ship_type_name == "Ferox"
      assert result2.damage_done == 300
      assert result2.is_final_blow == false
    end

    test "returns nil for non-existent character" do
      # Setup killmail
      killmail = %KillmailStruct{
        esi_data: %{
          "victim" => %{
            "character_id" => 98765,
            "character_name" => "Victim Pilot"
          },
          "attackers" => [
            %{
              "character_id" => 11111,
              "character_name" => "Attacker One"
            }
          ]
        }
      }

      # Call the function with a character ID that doesn't exist
      result = Validation.extract_character_involvement(killmail, 99999, :attacker)

      # Assert result is nil
      assert result == nil
    end
  end

  describe "validate_killmail/1" do
    test "passes validation for valid killmail data" do
      # Setup valid killmail data
      killmail_data = %{
        killmail_id: 12345,
        kill_time: DateTime.utc_now(),
        solar_system_id: 30_000_142,
        solar_system_name: "Jita",
        total_value: Decimal.new(15_000_000),
        victim_id: 98765,
        victim_name: "Victim Pilot",
        victim_ship_id: 587,
        victim_ship_name: "Rifter"
      }

      # Call the function under test
      result = Validation.validate_killmail(killmail_data)

      # Assert expected results
      assert {:ok, _} = result
    end

    test "fails validation for missing required fields" do
      # Setup invalid killmail data (missing required fields)
      killmail_data = %{
        killmail_id: 12345,
        # missing kill_time
        # missing solar_system_id
        solar_system_name: "Jita",
        total_value: Decimal.new(15_000_000)
      }

      # Call the function under test
      result = Validation.validate_killmail(killmail_data)

      # Assert expected results
      assert {:error, reason} = result
      assert String.contains?(reason, "solar_system_id")
    end
  end
end
