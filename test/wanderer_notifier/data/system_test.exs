defmodule WandererNotifier.Data.SystemTest do
  use ExUnit.Case, async: true
  alias WandererNotifier.Data.System

  describe "new/1" do
    test "creates a new system from a map" do
      attrs = %{
        system_id: 31_000_001,
        system_name: "J123456",
        security_status: -0.99,
        region_id: 10_000_001,
        region_name: "Deklein",
        constellation_id: 20_000_001,
        constellation_name: "Test Constellation",
        effect: "Wolf-Rayet",
        type: "C6",
        tracked: true,
        tracked_since: DateTime.utc_now()
      }

      result = System.new(attrs)

      assert %System{} = result
      assert result.system_id == 31_000_001
      assert result.system_name == "J123456"
      assert result.security_status == -0.99
      assert result.region_id == 10_000_001
      assert result.region_name == "Deklein"
      assert result.constellation_id == 20_000_001
      assert result.constellation_name == "Test Constellation"
      assert result.effect == "Wolf-Rayet"
      assert result.type == "C6"
      assert result.tracked == true
      assert %DateTime{} = result.tracked_since
    end

    test "creates a new system from keyword list" do
      now = DateTime.utc_now()

      attrs = [
        system_id: 31_000_002,
        system_name: "J987654",
        security_status: -0.75,
        tracked: true,
        tracked_since: now
      ]

      result = System.new(attrs)

      assert %System{} = result
      assert result.system_id == 31_000_002
      assert result.system_name == "J987654"
      assert result.security_status == -0.75
      assert result.tracked == true
      assert result.tracked_since == now
      # Default values
      assert result.region_id == nil
      assert result.effect == nil
    end
  end

  describe "from_map/1" do
    test "converts a map with string keys to System struct" do
      map = %{
        "system_id" => 31_000_003,
        "system_name" => "J555555",
        "security_status" => -1.0,
        "region_id" => 10_000_002,
        "region_name" => "Catch",
        "constellation_id" => 20_000_002,
        "constellation_name" => "Some Constellation",
        "effect" => "Cataclysmic Variable",
        "type" => "C5",
        "tracked" => true,
        "tracked_since" => "2023-07-15T12:30:45Z"
      }

      result = System.from_map(map)

      assert %System{} = result
      assert result.system_id == 31_000_003
      assert result.system_name == "J555555"
      assert result.security_status == -1.0
      assert result.region_id == 10_000_002
      assert result.region_name == "Catch"
      assert result.constellation_id == 20_000_002
      assert result.constellation_name == "Some Constellation"
      assert result.effect == "Cataclysmic Variable"
      assert result.type == "C5"
      assert result.tracked == true
      assert %DateTime{} = result.tracked_since
      assert result.tracked_since.year == 2023
      assert result.tracked_since.month == 7
      assert result.tracked_since.day == 15
    end

    test "converts a map with atom keys to System struct" do
      map = %{
        system_id: 31_000_004,
        system_name: "J111111",
        security_status: -0.8,
        tracked: false
      }

      result = System.from_map(map)

      assert %System{} = result
      assert result.system_id == 31_000_004
      assert result.system_name == "J111111"
      assert result.security_status == -0.8
      assert result.tracked == false
      assert result.tracked_since == nil
    end

    test "handles missing values with defaults" do
      map = %{
        "system_id" => 31_000_005,
        "system_name" => "J222222"
      }

      result = System.from_map(map)

      assert %System{} = result
      assert result.system_id == 31_000_005
      assert result.system_name == "J222222"
      assert result.security_status == nil
      assert result.tracked == false
      assert result.tracked_since == nil
    end

    test "handles DateTime objects in tracked_since" do
      now = DateTime.utc_now()

      map = %{
        "system_id" => 31_000_006,
        "system_name" => "J333333",
        "tracked" => true,
        "tracked_since" => now
      }

      result = System.from_map(map)

      assert %System{} = result
      assert result.tracked_since == now
    end
  end

  describe "parse_datetime/1" do
    test "delegates to DateTimeUtil.parse_datetime/1" do
      # This is a simple test to verify delegation works
      assert System.parse_datetime(nil) == nil
      assert System.parse_datetime("invalid") == nil

      valid_dt = "2023-08-20T15:30:45Z"
      parsed = System.parse_datetime(valid_dt)
      assert %DateTime{} = parsed
      assert parsed.year == 2023
      assert parsed.month == 8
      assert parsed.day == 20
    end
  end
end
