defmodule WandererNotifier.ESI.EntitiesTest do
  use ExUnit.Case, async: true

  alias WandererNotifier.Infrastructure.Adapters.ESI.Entities.{
    Character,
    Corporation,
    Alliance,
    SolarSystem
  }

  describe "Character entity" do
    test "creates Character struct from ESI data" do
      # Sample ESI character data
      character_data = %{
        "character_id" => 123_456,
        "name" => "Test Character",
        "corporation_id" => 789_012,
        "alliance_id" => 345_678,
        "security_status" => 0.5,
        "birthday" => "2020-01-01T00:00:00Z"
      }

      # Create Character struct
      character = Character.from_esi_data(character_data)

      # Verify fields
      assert character.character_id == 123_456
      assert character.name == "Test Character"
      assert character.corporation_id == 789_012
      assert character.alliance_id == 345_678
      assert character.security_status == 0.5
      assert character.birthday == ~U[2020-01-01 00:00:00Z]
    end

    test "converts Character struct to map" do
      # Create Character struct
      character = %Character{
        character_id: 123_456,
        name: "Test Character",
        corporation_id: 789_012,
        alliance_id: 345_678,
        security_status: 0.5,
        birthday: ~U[2020-01-01 00:00:00Z]
      }

      # Convert to map
      map = Character.to_map(character)

      # Verify fields
      assert map["character_id"] == 123_456
      assert map["name"] == "Test Character"
      assert map["corporation_id"] == 789_012
      assert map["alliance_id"] == 345_678
      assert map["security_status"] == 0.5
      assert map["birthday"] == "2020-01-01T00:00:00Z"
    end

    test "handles nil values gracefully" do
      # Sample ESI character data with nil values
      character_data = %{
        "character_id" => 123_456,
        "name" => "Test Character",
        "corporation_id" => 789_012
      }

      # Create Character struct
      character = Character.from_esi_data(character_data)

      # Verify fields
      assert character.character_id == 123_456
      assert character.name == "Test Character"
      assert character.corporation_id == 789_012
      assert character.alliance_id == nil
      assert character.security_status == nil
      assert character.birthday == nil
    end
  end

  describe "Corporation entity" do
    test "creates Corporation struct from ESI data" do
      # Sample ESI corporation data
      corporation_data = %{
        "corporation_id" => 789_012,
        "name" => "Test Corporation",
        "ticker" => "TSTC",
        "member_count" => 100,
        "alliance_id" => 345_678,
        "description" => "A test corporation",
        "date_founded" => "2020-01-01T00:00:00Z"
      }

      # Create Corporation struct
      corporation = Corporation.from_esi_data(corporation_data)

      # Verify fields
      assert corporation.corporation_id == 789_012
      assert corporation.name == "Test Corporation"
      assert corporation.ticker == "TSTC"
      assert corporation.member_count == 100
      assert corporation.alliance_id == 345_678
      assert corporation.description == "A test corporation"
      assert corporation.founding_date == ~U[2020-01-01 00:00:00Z]
    end

    test "converts Corporation struct to map" do
      # Create Corporation struct
      corporation = %Corporation{
        corporation_id: 789_012,
        name: "Test Corporation",
        ticker: "TSTC",
        member_count: 100,
        alliance_id: 345_678,
        description: "A test corporation",
        founding_date: ~U[2020-01-01 00:00:00Z]
      }

      # Convert to map
      map = Corporation.to_map(corporation)

      # Verify fields
      assert map["corporation_id"] == 789_012
      assert map["name"] == "Test Corporation"
      assert map["ticker"] == "TSTC"
      assert map["member_count"] == 100
      assert map["alliance_id"] == 345_678
      assert map["description"] == "A test corporation"
      assert map["date_founded"] == "2020-01-01T00:00:00Z"
    end
  end

  describe "Alliance entity" do
    test "creates Alliance struct from ESI data" do
      # Sample ESI alliance data
      alliance_data = %{
        "alliance_id" => 345_678,
        "name" => "Test Alliance",
        "ticker" => "TSTA",
        "executor_corporation_id" => 789_012,
        "creator_id" => 123_456,
        "date_founded" => "2020-01-01T00:00:00Z",
        "faction_id" => 555_555
      }

      # Create Alliance struct
      alliance = Alliance.from_esi_data(alliance_data)

      # Verify fields
      assert alliance.alliance_id == 345_678
      assert alliance.name == "Test Alliance"
      assert alliance.ticker == "TSTA"
      assert alliance.executor_corporation_id == 789_012
      assert alliance.creator_id == 123_456
      assert alliance.creation_date == ~U[2020-01-01 00:00:00Z]
      assert alliance.faction_id == 555_555
    end

    test "converts Alliance struct to map" do
      # Create Alliance struct
      alliance = %Alliance{
        alliance_id: 345_678,
        name: "Test Alliance",
        ticker: "TSTA",
        executor_corporation_id: 789_012,
        creator_id: 123_456,
        creation_date: ~U[2020-01-01 00:00:00Z],
        faction_id: 555_555
      }

      # Convert to map
      map = Alliance.to_map(alliance)

      # Verify fields
      assert map["alliance_id"] == 345_678
      assert map["name"] == "Test Alliance"
      assert map["ticker"] == "TSTA"
      assert map["executor_corporation_id"] == 789_012
      assert map["creator_id"] == 123_456
      assert map["date_founded"] == "2020-01-01T00:00:00Z"
      assert map["faction_id"] == 555_555
    end
  end

  describe "SolarSystem entity" do
    test "creates SolarSystem struct from ESI data" do
      # Sample ESI solar system data
      system_data = %{
        "system_id" => 30_000_142,
        "name" => "Jita",
        "constellation_id" => 20_000_020,
        "security_status" => 0.9,
        "position" => %{"x" => 1.0, "y" => 2.0, "z" => 3.0},
        "star_id" => 40_000_001,
        "planets" => [%{"planet_id" => 50_000_001}],
        "region_id" => 10_000_002
      }

      # Create SolarSystem struct
      system = SolarSystem.from_esi_data(system_data)

      # Verify fields
      assert system.system_id == 30_000_142
      assert system.name == "Jita"
      assert system.constellation_id == 20_000_020
      assert system.region_id == 10_000_002
      assert system.star_id == 40_000_001
      assert system.planets == [%{"planet_id" => 50_000_001}]
      assert system.security_status == 0.9
    end

    test "SolarSystem entity converts SolarSystem struct to map" do
      system = %SolarSystem{
        system_id: 30_000_142,
        name: "Test System",
        constellation_id: 20_000_020,
        security_status: 0.9,
        star_id: 40_000_001,
        planets: [%{"planet_id" => 50_000_001}],
        region_id: 10_000_002
      }

      map = SolarSystem.to_map(system)
      assert map["system_id"] == 30_000_142
      assert map["name"] == "Test System"
      assert map["constellation_id"] == 20_000_020
      assert map["security_status"] == 0.9
      assert map["star_id"] == 40_000_001
      assert map["planets"] == [%{"planet_id" => 50_000_001}]
      assert map["region_id"] == 10_000_002
    end

    test "calculates security band correctly" do
      high_sec = %SolarSystem{security_status: 0.5}
      low_sec = %SolarSystem{security_status: 0.4}
      null_sec = %SolarSystem{security_status: 0.0}
      unknown = %SolarSystem{security_status: nil}

      assert SolarSystem.security_band(high_sec) == "High"
      assert SolarSystem.security_band(low_sec) == "Low"
      assert SolarSystem.security_band(null_sec) == "Null"
      assert SolarSystem.security_band(unknown) == "Unknown"

      # Direct value tests
      assert SolarSystem.security_band(1.0) == "High"
      assert SolarSystem.security_band(0.5) == "High"
      assert SolarSystem.security_band(0.4) == "Low"
      assert SolarSystem.security_band(0.1) == "Low"
      assert SolarSystem.security_band(0.0) == "Null"
      assert SolarSystem.security_band(-0.1) == "Null"
    end
  end
end
