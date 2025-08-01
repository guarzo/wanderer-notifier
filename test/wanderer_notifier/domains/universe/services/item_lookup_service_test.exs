defmodule WandererNotifier.Domains.Universe.Services.ItemLookupServiceTest do
  use ExUnit.Case, async: false

  alias WandererNotifier.Domains.Universe.Services.ItemLookupService
  alias WandererNotifier.Domains.Universe.Services.FuzzworksService

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
      # Test with a common item - Tritanium (type_id: 34)
      name = ItemLookupService.get_item_name(34)
      assert is_binary(name)

      # Test with invalid type_id
      name = ItemLookupService.get_item_name(999_999_999)
      assert name == "Unknown Item"

      # Test with string type_id
      name = ItemLookupService.get_item_name("34")
      assert is_binary(name)
    end

    test "get_ship_name/1 returns a string" do
      # Test with a common ship - Rifter (type_id: 587)
      name = ItemLookupService.get_ship_name(587)
      assert is_binary(name)

      # Test with invalid ship type_id
      name = ItemLookupService.get_ship_name(999_999_999)
      assert name == "Unknown Item"
    end

    test "get_item_names/1 returns a map" do
      type_ids = [34, 587, 999_999_999]
      names = ItemLookupService.get_item_names(type_ids)

      assert is_map(names)
      assert Map.has_key?(names, "34")
      assert Map.has_key?(names, "587")
      assert Map.has_key?(names, "999999999")

      # All values should be strings
      Enum.each(names, fn {_id, name} ->
        assert is_binary(name)
      end)
    end

    test "is_ship?/1 works correctly" do
      # Test with a known ship - should work even without CSV data loaded
      # Most ship checking will depend on CSV data being loaded
      # Rifter
      result = ItemLookupService.is_ship?(587)
      assert is_boolean(result)

      # Test with invalid type_id
      result = ItemLookupService.is_ship?(999_999_999)
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
