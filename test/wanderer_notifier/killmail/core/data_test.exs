defmodule WandererNotifier.Killmail.Core.DataTest do
  use ExUnit.Case, async: true

  alias WandererNotifier.Killmail.Core.Data
  alias WandererNotifier.Resources.Killmail, as: KillmailResource

  # Sample test data
  @zkb_data %{
    "killmail_id" => 12345,
    "zkb" => %{
      "hash" => "abc123",
      "totalValue" => 1_000_000.0,
      "points" => 10,
      "npc" => false,
      "solo" => true
    }
  }

  @esi_data %{
    "killmail_id" => 12345,
    "killmail_time" => "2023-01-01T12:00:00Z",
    "solar_system_id" => 30_000_142,
    "victim" => %{
      "character_id" => 9876,
      "ship_type_id" => 587,
      "corporation_id" => 123_456
    },
    "attackers" => [
      %{
        "character_id" => 1234,
        "ship_type_id" => 34562,
        "final_blow" => true
      },
      %{
        "character_id" => 5678,
        "ship_type_id" => 33824,
        "final_blow" => false
      }
    ]
  }

  @resource %{
    killmail_id: 12345,
    zkb_hash: "abc123",
    kill_time: DateTime.from_iso8601("2023-01-01T12:00:00Z") |> elem(1),
    solar_system_id: 30_000_142,
    solar_system_name: "Jita",
    region_id: 10_000_002,
    region_name: "The Forge",
    victim_id: 9876,
    victim_name: "Test Victim",
    victim_ship_id: 587,
    victim_ship_name: "Rifter",
    victim_corporation_id: 123_456,
    victim_corporation_name: "Test Corp",
    full_attacker_data: [
      %{"character_id" => 1234, "ship_type_id" => 34562, "final_blow" => true},
      %{"character_id" => 5678, "ship_type_id" => 33824, "final_blow" => false}
    ],
    attacker_count: 2,
    final_blow_attacker_id: 1234,
    final_blow_attacker_name: "Test Attacker",
    final_blow_ship_id: 34562,
    final_blow_ship_name: "Drake",
    total_value: 1_000_000.0,
    points: 10,
    is_npc: false,
    is_solo: true
  }

  describe "from_zkb_and_esi/2" do
    test "creates Data from zkb and esi data" do
      # Setup test data
      zkb_data = %{
        "killmail_id" => 12_345,
        "zkb" => %{
          "hash" => "abc123",
          "totalValue" => 1_000_000,
          "points" => 10
        }
      }

      esi_data = %{
        "solar_system_id" => 30_000_142,
        "solar_system_name" => "Jita",
        "killmail_time" => "2023-01-01T12:00:00Z",
        "victim" => %{
          "character_id" => 123_456,
          "character_name" => "Test Victim"
        },
        "attackers" => [
          %{
            "character_id" => 789_012,
            "character_name" => "Test Attacker"
          }
        ]
      }

      # Create Data
      {:ok, data} = Data.from_zkb_and_esi(zkb_data, esi_data)

      # Verify it has the correct structure
      assert %Data{} = data

      # Verify it extracted the correct data
      assert data.killmail_id == 12_345
      assert data.raw_zkb_data["hash"] == "abc123"
      assert data.solar_system_id == 30_000_142
      assert data.victim_id == 123_456

      assert data.attackers == [
               %{
                 "character_id" => 789_012,
                 "character_name" => "Test Attacker"
               }
             ]

      refute data.persisted
    end

    test "handles atom keys in zkb_data" do
      zkb_data = %{
        killmail_id: 12_345,
        zkb: %{
          hash: "abc123",
          totalValue: 1_000_000
        }
      }

      esi_data = %{
        "solar_system_id" => 30_000_142
      }

      {:ok, data} = Data.from_zkb_and_esi(zkb_data, esi_data)

      assert %Data{} = data
      assert data.killmail_id == 12_345
      assert data.zkb_hash == "abc123"
    end

    test "handles missing/nil values gracefully" do
      # Both ZKB and ESI data need minimal fields
      zkb_data = %{"killmail_id" => 12345, "zkb" => %{"hash" => "abc123"}}
      esi_data = %{}

      {:ok, data} = Data.from_zkb_and_esi(zkb_data, esi_data)

      assert %Data{} = data
      assert data.killmail_id == 12345
      assert data.solar_system_id == nil
      assert data.solar_system_name == nil
      assert data.victim_id == nil
      assert data.victim_name == nil
    end
  end

  describe "from_resource/1" do
    test "creates Data from a resource" do
      # Create a mock Resource (we're not actually interacting with the database)
      resource = %KillmailResource{
        killmail_id: 12_345,
        solar_system_id: 30_000_142,
        solar_system_name: "Jita",
        kill_time: ~U[2023-01-01 12:00:00Z],
        victim_id: 123_456,
        victim_name: "Test Victim",
        full_victim_data: %{"character_id" => 123_456},
        full_attacker_data: [%{"character_id" => 789_012}]
      }

      # Create Data from resource
      {:ok, data} = Data.from_resource(resource)

      # Verify it has the correct structure
      assert %Data{} = data

      # Verify it extracted the correct data
      assert data.killmail_id == 12_345
      assert data.solar_system_id == 30_000_142
      assert data.solar_system_name == "Jita"
      assert data.kill_time == ~U[2023-01-01 12:00:00Z]
      assert data.victim_id == 123_456
      assert data.victim_name == "Test Victim"
      assert data.attackers == [%{"character_id" => 789_012}]
      assert data.persisted
    end
  end

  describe "from_map/1" do
    test "creates Data from a map" do
      map = %{
        "killmail_id" => 12_345,
        "solar_system_id" => 30_000_142
      }

      {:ok, data} = Data.from_map(map)

      assert %Data{} = data
      assert data.killmail_id == 12_345
      assert data.raw_data == map
    end

    test "creates Data from a map with zkb data" do
      map = %{
        "killmail_id" => 12_345,
        "zkb" => %{
          "hash" => "abc123"
        }
      }

      {:ok, data} = Data.from_map(map)

      assert %Data{} = data
      assert data.killmail_id == 12_345
      assert data.zkb_hash == "abc123"
    end

    test "returns error for invalid input" do
      assert {:error, _} = Data.from_map("not a map")
      assert {:error, _} = Data.from_map(nil)
    end
  end

  describe "merge/2" do
    test "merges two Data structs correctly" do
      data1 = %Data{
        killmail_id: 12_345,
        solar_system_id: 30_000_142
      }

      data2 = %Data{
        victim_id: 123_456,
        victim_name: "Test Victim"
      }

      {:ok, merged} = Data.merge(data1, data2)

      assert merged.killmail_id == 12_345
      assert merged.solar_system_id == 30_000_142
      assert merged.victim_id == 123_456
      assert merged.victim_name == "Test Victim"
    end

    test "non-nil values from second struct override first struct" do
      data1 = %Data{
        killmail_id: 12_345,
        solar_system_id: 30_000_142
      }

      data2 = %Data{
        killmail_id: 67_890,
        victim_id: 123_456
      }

      {:ok, merged} = Data.merge(data1, data2)

      assert merged.killmail_id == 67_890
      assert merged.solar_system_id == 30_000_142
      assert merged.victim_id == 123_456
    end

    test "nil values from second struct do not override first struct" do
      data1 = %Data{
        killmail_id: 12_345,
        solar_system_id: 30_000_142
      }

      data2 = %Data{
        victim_id: 123_456,
        solar_system_id: nil
      }

      {:ok, merged} = Data.merge(data1, data2)

      assert merged.killmail_id == 12_345
      assert merged.solar_system_id == 30_000_142
      assert merged.victim_id == 123_456
    end

    test "returns error for invalid inputs" do
      data = %Data{killmail_id: 12_345}

      assert {:error, _} = Data.merge(data, "not a Data struct")
      assert {:error, _} = Data.merge("not a Data struct", data)
    end
  end
end
