defmodule WandererNotifier.ESI.ServiceTest do
  use ExUnit.Case, async: true
  import Mox

  alias WandererNotifier.ESI.Service
  alias WandererNotifier.ESI.Entities.{Character, Corporation, Alliance, SolarSystem}
  alias WandererNotifier.Test.Support.Mocks, as: CacheMock

  # Make sure mocks are verified after each test
  setup :verify_on_exit!

  # Stub the Client module
  setup do
    # Set the cache mock as the implementation
    Application.put_env(:wanderer_notifier, :cache_repository, CacheMock)
    CacheMock.clear()

    # Set the ESI client mock as the implementation (unified)
    Application.put_env(:wanderer_notifier, :esi_service, WandererNotifier.Api.ESI.ServiceMock)

    # Setup for character tests
    character_data = %{
      "character_id" => 123_456,
      "name" => "Test Character",
      "corporation_id" => 789_012,
      "alliance_id" => 345_678,
      "security_status" => 0.5,
      "birthday" => "2020-01-01T00:00:00Z"
    }

    corporation_data = %{
      "corporation_id" => 789_012,
      "name" => "Test Corporation",
      "ticker" => "TSTC",
      "member_count" => 100,
      "alliance_id" => 345_678,
      "description" => "A test corporation",
      "date_founded" => "2020-01-01T00:00:00Z"
    }

    alliance_data = %{
      "alliance_id" => 345_678,
      "name" => "Test Alliance",
      "ticker" => "TSTA",
      "executor_corporation_id" => 789_012,
      "creator_id" => 123_456,
      "date_founded" => "2020-01-01T00:00:00Z",
      "faction_id" => 555_555
    }

    system_data = %{
      "system_id" => 30_000_142,
      "name" => "Jita",
      "constellation_id" => 20_000_020,
      "security_status" => 0.9,
      "security_class" => "B",
      "position" => %{"x" => 1.0, "y" => 2.0, "z" => 3.0},
      "star_id" => 40_000_001,
      "planets" => [%{"planet_id" => 50_000_001}],
      "region_id" => 10_000_002
    }

    # Define mocks for ESI client calls (unified)
    WandererNotifier.Api.ESI.ServiceMock
    |> stub(:get_character_info, fn id, _opts ->
      if id == 123_456, do: {:ok, character_data}, else: {:ok, %{}}
    end)
    |> stub(:get_corporation_info, fn id, _opts ->
      if id == 789_012, do: {:ok, corporation_data}, else: {:ok, %{}}
    end)
    |> stub(:get_alliance_info, fn id, _opts ->
      if id == 345_678, do: {:ok, alliance_data}, else: {:ok, %{}}
    end)
    |> stub(:get_system, fn id, _opts ->
      if id == 30_000_142, do: {:ok, system_data}, else: {:ok, %{}}
    end)

    # Return test data for use in tests
    %{
      character_data: character_data,
      corporation_data: corporation_data,
      alliance_data: alliance_data,
      system_data: system_data
    }
  end

  describe "get_character_struct/2" do
    test "returns a Character struct when successful", %{character_data: _character_data} do
      # Ensure cache is empty for this test
      CacheMock.delete(WandererNotifier.Cache.Keys.character(123_456))

      # Get character struct from ESI service
      {:ok, character} = Service.get_character_struct(123_456)

      # Verify that it's a Character struct with the correct data
      assert %Character{} = character
      assert character.character_id == 123_456
      assert character.name == "Test Character"
      assert character.corporation_id == 789_012
      assert character.alliance_id == 345_678
      assert character.security_status == 0.5
      assert character.birthday == ~U[2020-01-01 00:00:00Z]
    end

    test "uses cached data when available", %{character_data: character_data} do
      # Ensure the character is in the cache
      cache_key = WandererNotifier.Cache.Keys.character(123_456)
      CacheMock.put(cache_key, character_data)

      # Get character struct from ESI service
      {:ok, character} = Service.get_character_struct(123_456)

      # Verify that it's a Character struct with the correct data
      assert %Character{} = character
      assert character.character_id == 123_456
      assert character.name == "Test Character"
    end
  end

  describe "get_corporation_struct/2" do
    test "returns a Corporation struct when successful", %{corporation_data: _corporation_data} do
      # Ensure cache is empty for this test
      CacheMock.delete("corporation:789012")

      # Get corporation struct from ESI service
      {:ok, corporation} = Service.get_corporation_struct(789_012)

      # Verify that it's a Corporation struct with the correct data
      assert %Corporation{} = corporation
      assert corporation.corporation_id == 789_012
      assert corporation.name == "Test Corporation"
      assert corporation.ticker == "TSTC"
      assert corporation.member_count == 100
      assert corporation.alliance_id == 345_678
      assert corporation.description == "A test corporation"
      assert corporation.founding_date == ~U[2020-01-01 00:00:00Z]
    end
  end

  describe "get_alliance_struct/2" do
    test "returns an Alliance struct when successful", %{alliance_data: _alliance_data} do
      # Ensure cache is empty for this test
      CacheMock.delete("alliance:345678")

      # Get alliance struct from ESI service
      {:ok, alliance} = Service.get_alliance_struct(345_678)

      # Verify that it's an Alliance struct with the correct data
      assert %Alliance{} = alliance
      assert alliance.alliance_id == 345_678
      assert alliance.name == "Test Alliance"
      assert alliance.ticker == "TSTA"
      assert alliance.executor_corporation_id == 789_012
      assert alliance.creator_id == 123_456
      assert alliance.creation_date == ~U[2020-01-01 00:00:00Z]
      assert alliance.faction_id == 555_555
    end
  end

  describe "get_system_struct/2" do
    test "returns a SolarSystem struct when successful", %{system_data: _system_data} do
      # Ensure cache is empty for this test
      CacheMock.delete("system:30000142")

      # Get solar system struct from ESI service
      {:ok, system} = Service.get_system_struct(30_000_142)

      # Verify that it's a SolarSystem struct with the correct data
      assert %SolarSystem{} = system
      assert system.system_id == 30_000_142
      assert system.name == "Jita"
      assert system.constellation_id == 20_000_020
      assert system.security_status == 0.9
      assert system.security_class == "B"
      assert system.position == %{x: 1.0, y: 2.0, z: 3.0}
      assert system.star_id == 40_000_001
      assert system.planets == [%{"planet_id" => 50_000_001}]
      assert system.region_id == 10_000_002
    end
  end
end
