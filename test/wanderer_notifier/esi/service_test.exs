defmodule WandererNotifier.ESI.ServiceTest do
  use ExUnit.Case, async: true
  import Mox

  alias WandererNotifier.ESI.Service
  alias WandererNotifier.ESI.Entities.{Character, Corporation, Alliance}
  alias WandererNotifier.Test.Support.Mocks, as: CacheMock

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
  setup :verify_on_exit!

  # Stub the Client module
  setup do
    # Set the cache mock as the implementation
    Application.put_env(:wanderer_notifier, :cache_repository, CacheMock)
    CacheMock.clear()

    # Set the ESI client mock as the implementation (unified)
    Application.put_env(:wanderer_notifier, :esi_service, WandererNotifier.Api.ESI.ServiceMock)

    # Set HTTP client mock
    Application.put_env(
      :wanderer_notifier,
      :http_client,
      WandererNotifier.HttpClient.HttpoisonMock
    )

    # Define mocks for ESI client calls (unified)
    WandererNotifier.Api.ESI.ServiceMock
    |> stub(:get_character_info, &get_character_info/2)
    |> stub(:get_corporation_info, &get_corporation_info/2)
    |> stub(:get_alliance_info, &get_alliance_info/2)
    |> stub(:get_system, &get_system_info/2)

    # Add mock expectations for HTTP client calls
    WandererNotifier.HttpClient.HttpoisonMock
    |> stub(:get, fn url, _headers ->
      url
      |> get_data_for_url()
      |> wrap_response()
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

  defp get_system_info(id, _opts) do
    case id do
      30_000_142 -> {:ok, @system_data}
      _ -> {:error, :not_found}
    end
  end

  defp get_data_for_url(url) do
    cond do
      String.contains?(url, "characters/123456") -> @character_data
      String.contains?(url, "corporations/789012") -> @corporation_data
      String.contains?(url, "alliances/345678") -> @alliance_data
      String.contains?(url, "systems/30000142") -> @system_data
      true -> nil
    end
  end

  defp wrap_response(%{"error" => _} = body), do: {:ok, %{status_code: 404, body: body}}
  defp wrap_response(body), do: {:ok, %{status_code: 200, body: body}}

  describe "get_character_struct/2" do
    test "returns a Character struct when successful", %{character_data: _character_data} do
      # Ensure cache is empty for this test
      123_456
      |> WandererNotifier.Cache.Keys.character()
      |> CacheMock.delete()

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
end
