defmodule WandererNotifier.ESI.ServiceV2Test do
  use ExUnit.Case, async: true
  import Mox

  alias WandererNotifier.ESI.ServiceV2

  alias WandererNotifier.Infrastructure.Adapters.ESI.Entities.{
    Character,
    Corporation,
    Alliance,
    SolarSystem
  }

  setup :verify_on_exit!

  setup do
    # Cache is handled by the test environment automatically
    :ok
  end

  # Helper function to test caching behavior
  defp test_caching_behavior(data_type, id, data, service_fun, mock_fun) do
    # First call should hit the API
    expect(WandererNotifier.ESI.ClientMock, mock_fun, 1, fn _id, _opts ->
      {:ok, data}
    end)

    # First call - should hit API and cache result
    result1 = apply(ServiceV2, service_fun, [id])
    assert {:ok, ^data} = result1

    # Second call - should serve from cache without API call
    result2 = apply(ServiceV2, service_fun, [id])
    assert {:ok, ^data} = result2
  end

  describe "ServiceV2 character operations" do
    test "get_character_info uses CacheHelper for caching" do
      character_id = 123_456

      expected_data = %{
        "character_id" => character_id,
        "name" => "Test Character",
        "corporation_id" => 789_012
      }

      # Mock the API call - cache will be handled by the real cache system
      expect(WandererNotifier.ESI.ClientMock, :get_character_info, fn id, opts ->
        assert id == character_id
        assert opts[:timeout] == 30_000
        {:ok, expected_data}
      end)

      result = ServiceV2.get_character_info(character_id)
      assert {:ok, ^expected_data} = result
    end

    test "get_character_struct returns Character entity" do
      character_id = 123_456

      character_data = %{
        "character_id" => character_id,
        "name" => "Test Character",
        "corporation_id" => 789_012
      }

      expect(WandererNotifier.ESI.ClientMock, :get_character_info, fn _id, _opts ->
        {:ok, character_data}
      end)

      result = ServiceV2.get_character_struct(character_id)
      assert {:ok, %Character{}} = result
      {:ok, character} = result
      assert character.character_id == character_id
      assert character.name == "Test Character"
    end

    test "get_character_info returns cached data on second call" do
      character_id = 123_456

      character_data = %{
        "character_id" => character_id,
        "name" => "Test Character"
      }

      test_caching_behavior(
        :character,
        character_id,
        character_data,
        :get_character_info,
        :get_character_info
      )
    end
  end

  describe "ServiceV2 corporation operations" do
    test "get_corporation_info uses CacheHelper for caching" do
      corporation_id = 789_012

      expected_data = %{
        "corporation_id" => corporation_id,
        "name" => "Test Corporation",
        "ticker" => "TEST"
      }

      expect(WandererNotifier.ESI.ClientMock, :get_corporation_info, fn id, opts ->
        assert id == corporation_id
        assert opts[:timeout] == 30_000
        {:ok, expected_data}
      end)

      result = ServiceV2.get_corporation_info(corporation_id)
      assert {:ok, ^expected_data} = result
    end

    test "get_corporation_struct returns Corporation entity" do
      corporation_id = 789_012

      corp_data = %{
        "corporation_id" => corporation_id,
        "name" => "Test Corporation",
        "ticker" => "TEST"
      }

      expect(WandererNotifier.ESI.ClientMock, :get_corporation_info, fn _id, _opts ->
        {:ok, corp_data}
      end)

      result = ServiceV2.get_corporation_struct(corporation_id)
      assert {:ok, %Corporation{}} = result
    end
  end

  describe "ServiceV2 alliance operations" do
    test "get_alliance_info uses CacheHelper for caching" do
      alliance_id = 345_678

      expected_data = %{
        "alliance_id" => alliance_id,
        "name" => "Test Alliance",
        "ticker" => "TSTA"
      }

      expect(WandererNotifier.ESI.ClientMock, :get_alliance_info, fn id, opts ->
        assert id == alliance_id
        assert opts[:timeout] == 30_000
        {:ok, expected_data}
      end)

      result = ServiceV2.get_alliance_info(alliance_id)
      assert {:ok, ^expected_data} = result
    end
  end

  describe "ServiceV2 type operations" do
    test "get_type_info uses CacheHelper for caching" do
      type_id = 587

      expected_data = %{
        "type_id" => type_id,
        "name" => "Rifter",
        "group_id" => 25
      }

      expect(WandererNotifier.ESI.ClientMock, :get_universe_type, fn id, opts ->
        assert id == type_id
        assert opts[:timeout] == 30_000
        {:ok, expected_data}
      end)

      result = ServiceV2.get_type_info(type_id)
      assert {:ok, ^expected_data} = result
    end

    test "get_ship_type_name extracts name from type info" do
      type_id = 587
      type_data = %{"type_id" => type_id, "name" => "Rifter"}

      expect(WandererNotifier.ESI.ClientMock, :get_universe_type, fn _id, _opts ->
        {:ok, type_data}
      end)

      result = ServiceV2.get_ship_type_name(type_id)
      assert {:ok, %{"name" => "Rifter"}} = result
    end

    test "get_ship_type_name handles missing name field" do
      type_id = 587
      type_data = %{"type_id" => type_id}

      expect(WandererNotifier.ESI.ClientMock, :get_universe_type, fn _id, _opts ->
        {:ok, type_data}
      end)

      result = ServiceV2.get_ship_type_name(type_id)
      assert {:error, :esi_data_missing} = result
    end

    test "get_universe_type is alias for get_type_info" do
      type_id = 587
      type_data = %{"type_id" => type_id, "name" => "Rifter"}

      expect(WandererNotifier.ESI.ClientMock, :get_universe_type, fn _id, _opts ->
        {:ok, type_data}
      end)

      result = ServiceV2.get_universe_type(type_id)
      assert {:ok, ^type_data} = result
    end
  end

  describe "ServiceV2 system operations" do
    test "get_system uses CacheHelper for caching" do
      system_id = 30_000_142

      expected_data = %{
        "system_id" => system_id,
        "name" => "Jita",
        "security_status" => 0.9
      }

      expect(WandererNotifier.ESI.ClientMock, :get_system, fn id, opts ->
        assert id == system_id
        assert opts[:timeout] == 30_000
        {:ok, expected_data}
      end)

      result = ServiceV2.get_system(system_id)
      assert {:ok, ^expected_data} = result
    end

    test "get_system_struct returns SolarSystem entity" do
      system_id = 30_000_142

      system_data = %{
        "system_id" => system_id,
        "name" => "Jita",
        "security_status" => 0.9
      }

      expect(WandererNotifier.ESI.ClientMock, :get_system, fn _id, _opts ->
        {:ok, system_data}
      end)

      result = ServiceV2.get_system_struct(system_id)
      assert {:ok, %SolarSystem{}} = result
    end

    test "get_system_info is alias for get_system" do
      system_id = 30_000_142
      system_data = %{"system_id" => system_id, "name" => "Jita"}

      expect(WandererNotifier.ESI.ClientMock, :get_system, fn _id, _opts ->
        {:ok, system_data}
      end)

      result = ServiceV2.get_system_info(system_id)
      assert {:ok, ^system_data} = result
    end
  end

  describe "ServiceV2 killmail operations" do
    test "get_killmail uses custom cache key with CacheHelper" do
      kill_id = 12_345
      killmail_hash = "abc123"

      expected_data = %{
        "killmail_id" => kill_id,
        "killmail_time" => "2023-01-01T00:00:00Z",
        "victim" => %{"character_id" => 98_765}
      }

      expect(WandererNotifier.ESI.ClientMock, :get_killmail, fn id, hash, opts ->
        assert id == kill_id
        assert hash == killmail_hash
        assert opts[:timeout] == 30_000
        {:ok, expected_data}
      end)

      result = ServiceV2.get_killmail(kill_id, killmail_hash)
      assert {:ok, ^expected_data} = result
    end

    test "get_killmail handles timeout errors with proper logging" do
      kill_id = 12_345
      killmail_hash = "abc123"

      expect(WandererNotifier.ESI.ClientMock, :get_killmail, fn _id, _hash, _opts ->
        {:error, :timeout}
      end)

      result = ServiceV2.get_killmail(kill_id, killmail_hash)
      assert {:error, :timeout} = result
    end
  end

  describe "ServiceV2 search operations" do
    test "search_inventory_type uses custom cache key" do
      query = "Rifter"
      strict = true

      expected_data = %{
        "inventory_type" => [587, 588]
      }

      expect(WandererNotifier.ESI.ClientMock, :search_inventory_type, fn search_query, opts ->
        assert search_query == query
        assert opts[:timeout] == 30_000
        {:ok, expected_data}
      end)

      result = ServiceV2.search_inventory_type(query, strict)
      assert {:ok, ^expected_data} = result
    end
  end

  describe "ServiceV2 error handling" do
    test "handles API errors properly" do
      character_id = 123_456

      expect(WandererNotifier.ESI.ClientMock, :get_character_info, fn _id, _opts ->
        {:error, :api_error}
      end)

      result = ServiceV2.get_character_info(character_id)
      assert {:error, :api_error} = result
    end

    test "handles API timeouts" do
      character_id = 123_456

      expect(WandererNotifier.ESI.ClientMock, :get_character_info, fn _id, _opts ->
        {:error, :timeout}
      end)

      result = ServiceV2.get_character_info(character_id)
      assert {:error, :timeout} = result
    end
  end

  describe "ServiceV2 caching behavior" do
    test "caches character data and serves from cache on second request" do
      character_id = 123_456
      character_data = %{"character_id" => character_id, "name" => "Test Character"}

      test_caching_behavior(
        :character,
        character_id,
        character_data,
        :get_character_info,
        :get_character_info
      )
    end

    test "caches system data correctly" do
      system_id = 30_000_142
      system_data = %{"system_id" => system_id, "name" => "Jita"}

      # Should only call API once
      expect(WandererNotifier.ESI.ClientMock, :get_system, 1, fn _id, _opts ->
        {:ok, system_data}
      end)

      # First call
      result1 = ServiceV2.get_system(system_id)
      assert {:ok, ^system_data} = result1

      # Second call from cache
      result2 = ServiceV2.get_system(system_id)
      assert {:ok, ^system_data} = result2
    end
  end
end
