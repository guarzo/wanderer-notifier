defmodule WandererNotifier.Test.Fixtures.ApiResponses do
  @moduledoc """
  Provides fixture data for API responses used in tests.
  """

  def map_systems_response do
    %{
      "systems" => [
        %{
          "id" => "J123456",
          "name" => "Test System",
          "security_status" => -1.0,
          "region_id" => 10_000_001,
          "tracked" => true,
          "activity" => 25
        },
        %{
          "id" => "J654321",
          "name" => "Another System",
          "security_status" => -0.9,
          "region_id" => 10_000_002,
          "tracked" => false,
          "activity" => 5
        }
      ]
    }
  end

  def esi_character_response do
    %{
      "character_id" => 12345,
      "corporation_id" => 67890,
      "alliance_id" => 54321,
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
