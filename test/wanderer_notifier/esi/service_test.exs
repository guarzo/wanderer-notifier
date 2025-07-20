defmodule WandererNotifier.ESI.ServiceTest do
  use ExUnit.Case, async: true
  import Mox

  alias WandererNotifier.Infrastructure.Adapters.ESI.Service
  alias WandererNotifier.Infrastructure.Adapters.ESI.Entities.{Character, Corporation, Alliance}
  alias WandererNotifier.Cache.Facade
  alias WandererNotifier.ESI.ServiceMock

  # Test data
  @character_data %{
    "character_id" => 123_456,
    "name" => "Test Character",
    "corporation_id" => 789_012,
    "alliance_id" => 345_678,
    "security_status" => 0.5,
    "birthday" => "2020-01-01T00:00:00Z"
  }

  @corporation_data %{
    "corporation_id" => 789_012,
    "name" => "Test Corporation",
    "ticker" => "TSTC",
    "member_count" => 100,
    "alliance_id" => 345_678,
    "description" => "A test corporation",
    "date_founded" => "2020-01-01T00:00:00Z"
  }

  @alliance_data %{
    "alliance_id" => 345_678,
    "name" => "Test Alliance",
    "ticker" => "TSTA",
    "executor_corporation_id" => 789_012,
    "creator_id" => 123_456,
    "date_founded" => "2020-01-01T00:00:00Z",
    "faction_id" => 555_555
  }

  @system_data %{
    "system_id" => 30_000_142,
    "name" => "Test System",
    "constellation_id" => 20_000_020,
    "security_status" => 0.9,
    "security_class" => "B",
    "position" => %{"x" => 1.0, "y" => 2.0, "z" => 3.0},
    "star_id" => 40_000_001,
    "planets" => [%{"planet_id" => 50_000_001}],
    "region_id" => 10_000_002
  }

  # Make sure mocks are verified after each test
  setup :set_mox_from_context
  setup :verify_on_exit!

  # Stub the Client module
  setup do
    # Make sure the required registries are started
    if !Process.whereis(WandererNotifier.Cache.Registry) do
      {:ok, _} = Registry.start_link(keys: :unique, name: WandererNotifier.Cache.Registry)
    end

    # Make sure the cache process is started and running with the correct adapter
    cache_name = Application.get_env(:wanderer_notifier, :cache_name, :wanderer_test_cache)

    adapter =
      Application.get_env(:wanderer_notifier, :cache_adapter, WandererNotifier.Cache.ETSCache)

    # Start the ETS cache if it's not already running
    case adapter do
      WandererNotifier.Cache.ETSCache ->
        case GenServer.whereis({:via, Registry, {WandererNotifier.Cache.Registry, cache_name}}) do
          nil ->
            WandererNotifier.Cache.ETSCache.start_link([
              {:name, cache_name}
            ])

          _pid ->
            :ok
        end

      _ ->
        :ok
    end

    # Set the ESI client mock as the implementation
    Application.put_env(:wanderer_notifier, :esi_client, ServiceMock)

    # Define mocks for ESI client calls
    ServiceMock
    |> stub(:get_character_info, &get_character_info/2)
    |> stub(:get_corporation_info, &get_corporation_info/2)
    |> stub(:get_alliance_info, &get_alliance_info/2)
    |> stub(:get_system, &get_system_info/1)
    |> stub(:get_system, &get_system_info/2)
    |> stub(:get_system_info, &get_system_info/2)
    |> stub(:get_type_info, fn _id, _opts -> {:ok, %{"name" => "Test Ship"}} end)
    |> stub(:get_system_kills, fn _id, _limit, _opts -> {:ok, []} end)
    |> stub(:get_character, &get_character_info/2)
    |> stub(:get_type, fn _id, _opts -> {:ok, %{"name" => "Test Ship"}} end)
    |> stub(:get_ship_type_name, fn _id, _opts -> {:ok, %{"name" => "Test Ship"}} end)
    |> stub(:get_killmail, fn _id, _hash ->
      {:ok,
       %{
         "killmail_id" => 123,
         "killmail_time" => "2020-01-01T00:00:00Z",
         "solar_system_id" => 30_000_142,
         "victim" => %{
           "character_id" => 100,
           "corporation_id" => 300,
           "alliance_id" => 400,
           "ship_type_id" => 200
         }
       }}
    end)
    |> stub(:get_killmail, fn _id, _hash, _opts ->
      {:ok,
       %{
         "killmail_id" => 123,
         "killmail_time" => "2020-01-01T00:00:00Z",
         "solar_system_id" => 30_000_142,
         "victim" => %{
           "character_id" => 100,
           "corporation_id" => 300,
           "alliance_id" => 400,
           "ship_type_id" => 200
         }
       }}
    end)

    # Return test data for use in tests
    %{
      character_data: @character_data,
      corporation_data: @corporation_data,
      alliance_data: @alliance_data,
      system_data: @system_data
    }
  end

  defp get_character_info(id, _opts) do
    case id do
      123_456 -> {:ok, @character_data}
      _ -> {:error, :not_found}
    end
  end

  defp get_corporation_info(id, _opts) do
    case id do
      789_012 -> {:ok, @corporation_data}
      _ -> {:error, :not_found}
    end
  end

  defp get_alliance_info(id, _opts) do
    case id do
      345_678 -> {:ok, @alliance_data}
      _ -> {:error, :not_found}
    end
  end

  defp get_system_info(id) do
    get_system_info(id, [])
  end

  defp get_system_info(id, _opts) do
    case id do
      30_000_142 -> {:ok, @system_data}
      _ -> {:error, :not_found}
    end
  end

  describe "get_character_struct/2" do
    test "returns a Character struct when successful", %{character_data: _character_data} do
      # Ensure cache is empty for this test
      123_456
      |> WandererNotifier.Cache.Keys.character()
      |> Facade.delete()

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
      Facade.put_character(123_456, character_data)

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
      789_012
      |> WandererNotifier.Cache.Keys.corporation()
      |> Facade.delete()

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
      345_678
      |> WandererNotifier.Cache.Keys.alliance()
      |> Facade.delete()

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

  describe "get_killmail/2" do
    test "returns killmail data" do
      assert {:ok, killmail} = Service.get_killmail(123, "hash")

      assert killmail == %{
               "killmail_id" => 123,
               "killmail_time" => "2020-01-01T00:00:00Z",
               "solar_system_id" => 30_000_142,
               "victim" => %{
                 "character_id" => 100,
                 "corporation_id" => 300,
                 "alliance_id" => 400,
                 "ship_type_id" => 200
               }
             }
    end
  end

  describe "get_killmail/3" do
    test "returns killmail data with opts" do
      assert {:ok, killmail} = Service.get_killmail(123, "hash", [])

      assert killmail == %{
               "killmail_id" => 123,
               "killmail_time" => "2020-01-01T00:00:00Z",
               "solar_system_id" => 30_000_142,
               "victim" => %{
                 "character_id" => 100,
                 "corporation_id" => 300,
                 "alliance_id" => 400,
                 "ship_type_id" => 200
               }
             }
    end
  end
end
