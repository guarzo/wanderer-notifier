defmodule WandererNotifier.KillmailProcessing.ValidatorTest do
  use ExUnit.Case

  alias WandererNotifier.KillmailProcessing.{KillmailData, Validator}

  describe "validate_complete_data/1" do
    test "returns :ok for valid killmail" do
      killmail = %KillmailData{
        killmail_id: 12_345,
        solar_system_id: 30_000_142,
        solar_system_name: "Jita",
        victim: %{"character_id" => 123_456}
      }

      assert Validator.validate_complete_data(killmail) == :ok
    end

    test "returns error for missing killmail_id" do
      killmail = %KillmailData{
        solar_system_id: 30_000_142,
        solar_system_name: "Jita",
        victim: %{"character_id" => 123_456}
      }

      assert {:error, "Killmail ID missing"} = Validator.validate_complete_data(killmail)
    end

    test "returns error for missing solar_system_id" do
      killmail = %KillmailData{
        killmail_id: 12_345,
        solar_system_name: "Jita",
        victim: %{"character_id" => 123_456}
      }

      assert {:error, "Solar system ID missing"} = Validator.validate_complete_data(killmail)
    end

    test "returns error for missing solar_system_name" do
      killmail = %KillmailData{
        killmail_id: 12_345,
        solar_system_id: 30_000_142,
        victim: %{"character_id" => 123_456}
      }

      assert {:error, "Solar system name missing"} = Validator.validate_complete_data(killmail)
    end

    test "returns error for missing victim data" do
      killmail = %KillmailData{
        killmail_id: 12_345,
        solar_system_id: 30_000_142,
        solar_system_name: "Jita"
      }

      assert {:error, "Victim data missing"} = Validator.validate_complete_data(killmail)
    end

    test "validates mixed map data" do
      # Create a killmail with mixed data formats
      killmail = %{
        killmail_id: 12_345,
        solar_system_id: 30_000_142,
        solar_system_name: "Jita",
        esi_data: %{
          "victim" => %{"character_id" => 123_456}
        }
      }

      assert Validator.validate_complete_data(killmail) == :ok
    end

    test "validates resource data" do
      # Mock a resource object
      killmail = %WandererNotifier.Resources.Killmail{
        killmail_id: 12_345,
        solar_system_id: 30_000_142,
        solar_system_name: "Jita",
        full_victim_data: %{"character_id" => 123_456}
      }

      assert Validator.validate_complete_data(killmail) == :ok
    end
  end
end
