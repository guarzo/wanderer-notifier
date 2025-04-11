defmodule WandererNotifier.KillmailProcessing.ValidatorTest do
  use ExUnit.Case

  alias WandererNotifier.KillmailProcessing.{KillmailData, Validator}

  describe "validate_complete_data/1" do
    test "returns :ok for valid killmail" do
      killmail = %KillmailData{
        killmail_id: 12_345,
        zkb_hash: "abc123",
        solar_system_id: 30_000_142,
        solar_system_name: "Jita",
        kill_time: DateTime.utc_now(),
        victim_id: 123_456,
        victim_name: "Test Character",
        victim_ship_id: 34562,
        victim_ship_name: "Test Ship"
      }

      assert Validator.validate(killmail) == :ok
    end

    test "returns error for missing killmail_id" do
      killmail = %KillmailData{
        zkb_hash: "abc123",
        solar_system_id: 30_000_142,
        solar_system_name: "Jita",
        kill_time: DateTime.utc_now(),
        victim_id: 123_456,
        victim_name: "Test Character",
        victim_ship_id: 34562,
        victim_ship_name: "Test Ship"
      }

      assert {:error, errors} = Validator.validate(killmail)
      assert Enum.any?(errors, fn {field, _} -> field == :killmail_id end)
    end

    test "returns error for missing solar_system_id" do
      killmail = %KillmailData{
        killmail_id: 12_345,
        zkb_hash: "abc123",
        solar_system_name: "Jita",
        kill_time: DateTime.utc_now(),
        victim_id: 123_456,
        victim_name: "Test Character",
        victim_ship_id: 34562,
        victim_ship_name: "Test Ship"
      }

      assert {:error, errors} = Validator.validate(killmail)
      assert Enum.any?(errors, fn {field, _} -> field == :solar_system_id end)
    end

    test "returns error for missing solar_system_name" do
      killmail = %KillmailData{
        killmail_id: 12_345,
        zkb_hash: "abc123",
        solar_system_id: 30_000_142,
        kill_time: DateTime.utc_now(),
        victim_id: 123_456,
        victim_name: "Test Character",
        victim_ship_id: 34562,
        victim_ship_name: "Test Ship"
      }

      assert {:error, errors} = Validator.validate(killmail)
      assert Enum.any?(errors, fn {field, _} -> field == :solar_system_name end)
    end

    test "returns error for missing victim data" do
      killmail = %KillmailData{
        killmail_id: 12_345,
        zkb_hash: "abc123",
        solar_system_id: 30_000_142,
        solar_system_name: "Jita",
        kill_time: DateTime.utc_now()
        # Missing victim fields
      }

      assert {:error, errors} = Validator.validate(killmail)
      assert Enum.any?(errors, fn {field, _} -> field == :victim_id end)
    end

    test "validates mixed map data" do
      # This test should be updated to use the new KillmailData format or removed
      # since the Validator now expects a KillmailData struct
      mixed_map = %{
        "some_field" => "some_value"
      }

      assert {:error, errors} = Validator.validate(mixed_map)
      assert Enum.any?(errors, fn {field, _} -> field == :invalid_type end)
    end

    test "validates resource data" do
      # This test should be updated or removed if the Validator now only accepts KillmailData
      resource = "not a KillmailData struct"
      assert {:error, errors} = Validator.validate(resource)
      assert Enum.any?(errors, fn {field, _} -> field == :invalid_type end)
    end
  end
end
