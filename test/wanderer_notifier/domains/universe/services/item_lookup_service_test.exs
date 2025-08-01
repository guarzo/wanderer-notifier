defmodule WandererNotifier.Domains.Universe.Services.ItemLookupServiceTest do
  use ExUnit.Case, async: false
  import Mox

  alias WandererNotifier.Domains.Universe.Services.ItemLookupService
  alias WandererNotifier.Domains.Universe.Services.FuzzworksService
  alias WandererNotifier.Infrastructure.Cache

  setup :verify_on_exit!

  describe "ItemLookupService basic functionality" do
    test "can start and get status" do
      # Since the service is started by the application,
      # we just need to verify it's running and can respond
      status = ItemLookupService.get_status()

      assert is_map(status)
      assert Map.has_key?(status, :loaded)
      assert Map.has_key?(status, :loading)
    end

    test "get_item_name/1 returns a string" do
      # Clear cache to ensure fresh test
      Cache.delete("esi:universe_type:34")
      Cache.delete("esi:universe_type:999999999")

      # Mock ESI response for Tritanium
      expect(WandererNotifier.HTTPMock, :request, fn
        :get, "https://esi.evetech.net/latest/universe/types/34/", nil, [], _opts ->
          {:ok, %{status_code: 200, body: %{"type_id" => 34, "name" => "Tritanium"}}}
      end)

      # Mock ESI response for invalid type_id
      expect(WandererNotifier.HTTPMock, :request, fn :get,
                                                     "https://esi.evetech.net/latest/universe/types/999999999/",
                                                     nil,
                                                     [],
                                                     _opts ->
        {:ok, %{status_code: 404}}
      end)

      # Test with a common item - Tritanium (type_id: 34)
      name = ItemLookupService.get_item_name(34)
      assert name == "Tritanium"

      # Test with invalid type_id
      name = ItemLookupService.get_item_name(999_999_999)
      assert name == "Unknown Item"

      # Test with string type_id (will use cache from first call)
      name = ItemLookupService.get_item_name("34")
      assert name == "Tritanium"
    end

    test "get_ship_name/1 returns a string" do
      # Clear cache to ensure fresh test
      Cache.delete("esi:universe_type:587")
      Cache.delete("esi:universe_type:999999999")

      # Mock ESI response for Rifter
      expect(WandererNotifier.HTTPMock, :request, fn :get,
                                                     "https://esi.evetech.net/latest/universe/types/587/",
                                                     nil,
                                                     [],
                                                     _opts ->
        {:ok, %{status_code: 200, body: %{"type_id" => 587, "name" => "Rifter"}}}
      end)

      # Mock ESI response for invalid ship type_id
      expect(WandererNotifier.HTTPMock, :request, fn :get,
                                                     "https://esi.evetech.net/latest/universe/types/999999999/",
                                                     nil,
                                                     [],
                                                     _opts ->
        {:ok, %{status_code: 404}}
      end)

      # Test with a common ship - Rifter (type_id: 587)
      name = ItemLookupService.get_ship_name(587)
      assert name == "Rifter"

      # Test with invalid ship type_id
      name = ItemLookupService.get_ship_name(999_999_999)
      assert name == "Unknown Item"
    end

    test "get_item_names/1 returns a map" do
      # Clear cache to ensure fresh test
      Cache.delete("esi:universe_type:34")
      Cache.delete("esi:universe_type:587")
      Cache.delete("esi:universe_type:999999999")

      # Mock ESI responses
      expect(WandererNotifier.HTTPMock, :request, 3, fn
        :get, "https://esi.evetech.net/latest/universe/types/34/", nil, [], _opts ->
          {:ok, %{status_code: 200, body: %{"type_id" => 34, "name" => "Tritanium"}}}

        :get, "https://esi.evetech.net/latest/universe/types/587/", nil, [], _opts ->
          {:ok, %{status_code: 200, body: %{"type_id" => 587, "name" => "Rifter"}}}

        :get, "https://esi.evetech.net/latest/universe/types/999999999/", nil, [], _opts ->
          {:ok, %{status_code: 404}}
      end)

      type_ids = [34, 587, 999_999_999]
      names = ItemLookupService.get_item_names(type_ids)

      assert is_map(names)
      assert Map.has_key?(names, "34")
      assert Map.has_key?(names, "587")
      assert Map.has_key?(names, "999999999")

      assert names["34"] == "Tritanium"
      assert names["587"] == "Rifter"
      assert names["999999999"] == "Unknown Item"

      # All values should be strings
      Enum.each(names, fn {_id, name} ->
        assert is_binary(name)
      end)
    end

    test "ship?/1 works correctly" do
      # Test with a known ship - should work even without CSV data loaded
      # Most ship checking will depend on CSV data being loaded
      # Rifter
      result = ItemLookupService.ship?(587)
      assert is_boolean(result)

      # Test with invalid type_id
      result = ItemLookupService.ship?(999_999_999)
      assert result == false
    end
  end

  describe "FuzzworksService functionality" do
    test "csv_files_exist?/0 returns boolean" do
      result = FuzzworksService.csv_files_exist?()
      assert is_boolean(result)
    end

    test "get_csv_file_paths/0 returns map with paths" do
      paths = FuzzworksService.get_csv_file_paths()

      assert is_map(paths)
      assert Map.has_key?(paths, :types_path)
      assert Map.has_key?(paths, :groups_path)
      assert is_binary(paths.types_path)
      assert is_binary(paths.groups_path)
    end

    test "get_csv_file_info/0 returns info map" do
      info = FuzzworksService.get_csv_file_info()

      assert is_map(info)
      assert Map.has_key?(info, :types_file)
      assert Map.has_key?(info, :groups_file)
      assert Map.has_key?(info, :all_present)
      assert is_boolean(info.all_present)
    end
  end
end
