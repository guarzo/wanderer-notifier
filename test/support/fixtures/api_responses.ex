defmodule WandererNotifier.Test.Fixtures.ApiResponses do
  @moduledoc """
  Provides fixture data for API responses used in tests.
  """

  def map_systems_response do
    %{
      "data" => %{
        "systems" => [
          %{
            "id" => "sys-uuid-1",
            "solar_system_id" => 30_000_142,
            "solar_system_name" => "Jita",
            "custom_name" => "Trade Hub Central",
            "temporary_name" => nil,
            "description" => "Main trade hub",
            "region_name" => "The Forge",
            "locked" => false,
            "visible" => true,
            "position_x" => 100.5,
            "position_y" => 200.3,
            "status" => "active",
            "tag" => "HQ",
            "labels" => ["market", "hub"],
            "map_id" => "map-uuid-1"
          },
          %{
            "id" => "sys-uuid-2",
            "solar_system_id" => 31_000_001,
            "solar_system_name" => "J123456",
            "custom_name" => "Home System",
            "temporary_name" => nil,
            "description" => "Our wormhole home",
            "region_name" => "A-R00001",
            "locked" => false,
            "visible" => true,
            "position_x" => 150.0,
            "position_y" => 250.0,
            "status" => "active",
            "tag" => nil,
            "labels" => [],
            "map_id" => "map-uuid-1"
          },
          %{
            "id" => "sys-uuid-3",
            "solar_system_id" => 31_000_002,
            "solar_system_name" => "J654321",
            "custom_name" => nil,
            "temporary_name" => nil,
            "description" => nil,
            "region_name" => "B-R00002",
            "locked" => false,
            "visible" => true,
            "position_x" => 200.0,
            "position_y" => 300.0,
            "status" => "active",
            "tag" => nil,
            "labels" => [],
            "map_id" => "map-uuid-1"
          }
        ]
      }
    }
  end

  def esi_character_response do
    %{
      "character_id" => 12_345,
      "corporation_id" => 67_890,
      "alliance_id" => 54_321,
      "name" => "Test Character",
      "security_status" => 5.0
    }
  end

  def zkill_message do
    %{
      "killID" => 12_345_678,
      "killmail_time" => "2023-06-15T12:34:56Z",
      "solar_system_id" => 30_000_142,
      "victim" => %{
        "character_id" => 12_345,
        "corporation_id" => 67_890,
        "ship_type_id" => 582
      },
      "attackers" => [
        %{
          "character_id" => 98_765,
          "corporation_id" => 54_321,
          "ship_type_id" => 11_567
        }
      ],
      "zkb" => %{
        "totalValue" => 100_000_000.0,
        "points" => 10
      }
    }
  end
end
