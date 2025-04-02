defmodule WandererNotifier.Data.Cache.HelpersTest do
  use ExUnit.Case, async: false
  require Logger

  import Mox

  # Setup mocks before tests
  setup :verify_on_exit!

  alias WandererNotifier.Data.Cache.Helpers, as: CacheHelpers
  alias WandererNotifier.Data.Cache.RepositoryMock
  alias WandererNotifier.Data.MapSystem

  setup do
    # Set the mock as the implementation for Repository
    Application.put_env(
      :wanderer_notifier,
      :cache_repository,
      WandererNotifier.Data.Cache.RepositoryMock
    )

    # Ensure ETS tables exist
    table_opts = [
      :named_table,
      :public,
      :set,
      {:write_concurrency, true},
      {:read_concurrency, true}
    ]

    # Create tables if they don't exist
    if :ets.whereis(:cache_table) == :undefined do
      :ets.new(:cache_table, table_opts)
    end

    if :ets.whereis(:locks_table) == :undefined do
      :ets.new(:locks_table, table_opts)
    end

    # Clean up any existing data
    :ets.delete_all_objects(:cache_table)
    :ets.delete_all_objects(:locks_table)

    # Default behaviors - empty cache
    RepositoryMock
    |> stub(:get, fn key ->
      case key do
        "map:systems" -> []
        "tracked:systems" -> []
        "map:characters" -> []
        "tracked:characters" -> []
        "map:system:" <> _id -> nil
        "map:character:" <> _id -> nil
        _ -> nil
      end
    end)
    |> stub(:put, fn _key, _value -> :ok end)
    |> stub(:set, fn _key, _value, _ttl -> :ok end)
    |> stub(:delete, fn _key -> :ok end)
    |> stub(:clear, fn -> :ok end)
    |> stub(:get_and_update, fn _key, fun ->
      {old, new} = fun.(nil)
      {old, new}
    end)

    :ok
  end

  # Basic sanity testing for public API
  describe "get_tracked_systems/0" do
    test "returns empty list when no systems are tracked" do
      result = CacheHelpers.get_tracked_systems()
      assert is_list(result)
      assert result == []
    end
  end

  describe "add_system_to_tracked/2" do
    test "adds system with integer ID" do
      system_data = %{name: "Test System"}
      system_id = 12_345

      RepositoryMock
      |> expect(:get, fn "map:system:12345" -> nil end)
      |> expect(:put, fn "map:system:12345", ^system_data -> :ok end)
      |> expect(:put, fn "tracked:system:12345", true -> :ok end)
      |> expect(:get, fn "tracked:systems" -> [] end)
      |> expect(:put, fn "tracked:systems", [%{"system_id" => "12345"}] -> :ok end)

      result = CacheHelpers.add_system_to_tracked(system_id, system_data)
      assert result == :ok
    end

    test "adds system with string ID" do
      system_data = %{name: "Test System"}
      system_id = "12345"

      RepositoryMock
      |> expect(:get, fn "map:system:12345" -> nil end)
      |> expect(:put, fn "map:system:12345", ^system_data -> :ok end)
      |> expect(:put, fn "tracked:system:12345", true -> :ok end)
      |> expect(:get, fn "tracked:systems" -> [] end)
      |> expect(:put, fn "tracked:systems", [%{"system_id" => "12345"}] -> :ok end)

      result = CacheHelpers.add_system_to_tracked(system_id, system_data)
      assert result == :ok
    end

    test "handles adding duplicate system IDs" do
      system_data = %{name: "Test System Updated"}
      system_id = 12_345
      existing_systems = [%{"system_id" => "12345"}]

      RepositoryMock
      |> expect(:get, fn "map:system:12345" -> %{"system_id" => "12345"} end)
      |> expect(:put, fn "tracked:system:12345", true -> :ok end)
      |> expect(:get, fn "tracked:systems" -> existing_systems end)
      |> expect(:put, fn "tracked:systems", ^existing_systems -> :ok end)

      result = CacheHelpers.add_system_to_tracked(system_id, system_data)
      assert result == :ok
    end

    test "handles MapSystem struct" do
      system = %MapSystem{
        id: "168dae37-2e19-4982-8936-d945a8485420",
        solar_system_id: 30_000_142,
        name: "Jita",
        original_name: "Jita",
        temporary_name: nil,
        locked: true,
        class_title: nil,
        effect_name: nil,
        region_name: "The Forge",
        statics: [],
        static_details: [],
        system_type: :kspace,
        type_description: "High-sec",
        is_shattered: false,
        sun_type_id: 123
      }

      RepositoryMock
      |> expect(:get, fn "map:system:30000142" -> nil end)
      |> expect(:put, fn "map:system:30000142", ^system -> :ok end)
      |> expect(:put, fn "tracked:system:30000142", true -> :ok end)
      |> expect(:get, fn "tracked:systems" -> [] end)
      |> expect(:put, fn "tracked:systems", [%{"system_id" => "30000142"}] -> :ok end)

      result = CacheHelpers.add_system_to_tracked(system.solar_system_id, system)
      assert result == :ok
    end
  end

  describe "remove_system_from_tracked/1" do
    test "removes system when it exists in tracked list" do
      RepositoryMock
      |> expect(:get, fn "tracked:systems" -> [%{"system_id" => "12345"}] end)
      |> expect(:put, fn "tracked:systems", [] -> :ok end)
      |> expect(:delete, fn "tracked:system:12345" -> :ok end)

      result = CacheHelpers.remove_system_from_tracked(12_345)
      assert result == :ok
    end

    test "handles removing non-existent system gracefully" do
      RepositoryMock
      |> expect(:get, fn "tracked:systems" -> [] end)
      |> expect(:put, fn "tracked:systems", [] -> :ok end)
      |> expect(:delete, fn "tracked:system:999999" -> :ok end)

      result = CacheHelpers.remove_system_from_tracked(999_999)
      assert result == :ok
    end

    test "handles string ID for removal" do
      RepositoryMock
      |> expect(:get, fn "tracked:systems" -> [%{"system_id" => "12345"}] end)
      |> expect(:put, fn "tracked:systems", [] -> :ok end)
      |> expect(:delete, fn "tracked:system:12345" -> :ok end)

      result = CacheHelpers.remove_system_from_tracked("12345")
      assert result == :ok
    end
  end

  describe "get_tracked_characters/0" do
    test "returns empty list when no characters are tracked" do
      result = CacheHelpers.get_tracked_characters()
      assert is_list(result)
      assert result == []
    end
  end

  describe "add_character_to_tracked/2" do
    test "adds character with integer ID" do
      character_data = %{
        name: "Test Character",
        eve_id: "12345",
        character_id: "12345"
      }

      RepositoryMock
      |> expect(:get, fn "map:character:12345" -> nil end)
      |> expect(:put, fn "map:character:12345", ^character_data -> :ok end)
      |> expect(:put, fn "tracked:character:12345", true -> :ok end)

      result = CacheHelpers.add_character_to_tracked(12_345, character_data)
      assert result == :ok
    end

    test "adds character with string ID" do
      character_data = %{
        name: "Test Character",
        eve_id: "12345",
        character_id: "12345"
      }

      RepositoryMock
      |> expect(:get, fn "map:character:12345" -> nil end)
      |> expect(:put, fn "map:character:12345", ^character_data -> :ok end)
      |> expect(:put, fn "tracked:character:12345", true -> :ok end)

      result = CacheHelpers.add_character_to_tracked("12345", character_data)
      assert result == :ok
    end

    test "handles adding duplicate character IDs" do
      character_data = %{
        name: "Test Character Updated",
        eve_id: "12345",
        character_id: "12345"
      }

      RepositoryMock
      |> expect(:get, fn "map:character:12345" -> %{"character_id" => "12345"} end)
      |> expect(:put, fn "tracked:character:12345", true -> :ok end)

      result = CacheHelpers.add_character_to_tracked(12_345, character_data)
      assert result == :ok
    end
  end

  describe "remove_character_from_tracked/1" do
    test "removes character when it exists in tracked list" do
      RepositoryMock
      |> expect(:get, fn "tracked:characters" -> [%{"character_id" => "12345"}] end)
      |> expect(:put, fn "tracked:characters", [] -> :ok end)
      |> expect(:delete, fn "tracked:character:12345" -> :ok end)

      result = CacheHelpers.remove_character_from_tracked(12_345)
      assert result == :ok
    end

    test "handles removing non-existent character gracefully" do
      RepositoryMock
      |> expect(:get, fn "tracked:characters" -> [] end)
      |> expect(:put, fn "tracked:characters", [] -> :ok end)
      |> expect(:delete, fn "tracked:character:999999" -> :ok end)

      result = CacheHelpers.remove_character_from_tracked(999_999)
      assert result == :ok
    end

    test "handles string ID for removal" do
      RepositoryMock
      |> expect(:get, fn "tracked:characters" -> [%{"character_id" => "12345"}] end)
      |> expect(:put, fn "tracked:characters", [] -> :ok end)
      |> expect(:delete, fn "tracked:character:12345" -> :ok end)

      result = CacheHelpers.remove_character_from_tracked("12345")
      assert result == :ok
    end
  end
end
