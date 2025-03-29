defmodule WandererNotifier.Helpers.CacheHelpersTest do
  use ExUnit.Case, async: false
  require Logger

  import Mox
  # Setup mocks before tests
  setup :verify_on_exit!
  alias WandererNotifier.Data.Cache.RepositoryMock
  alias WandererNotifier.Helpers.CacheHelpers

  setup do
    # Set the mock as the implementation for Repository
    Application.put_env(
      :wanderer_notifier,
      :cache_repository,
      WandererNotifier.Data.Cache.RepositoryMock
    )

    # Default behaviors - empty cache
    RepositoryMock
    |> stub(:get, fn key ->
      case key do
        "map:systems" -> []
        "tracked:systems" -> []
        "map:characters" -> []
        "tracked:characters" -> []
        _ -> nil
      end
    end)
    |> stub(:put, fn _key, _value -> :ok end)
    |> stub(:delete, fn _key -> :ok end)
    |> stub(:get_and_update, fn _key, fun ->
      {old_value, new_value} = fun.(nil)
      {old_value, new_value}
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
      RepositoryMock
      |> expect(:get_and_update, fn "tracked:systems", _fun -> {[], :added} end)
      |> expect(:put, fn "tracked:system:12345", true -> :ok end)
      |> expect(:get, fn "map:system:12345" -> nil end)
      |> expect(:put, fn "map:system:12345", _system_data -> :ok end)

      result = CacheHelpers.add_system_to_tracked(12_345, %{name: "Test System"})
      assert result == :ok
    end

    test "adds system with string ID" do
      RepositoryMock
      |> expect(:get_and_update, fn "tracked:systems", _fun -> {[], :added} end)
      |> expect(:put, fn "tracked:system:12345", true -> :ok end)
      |> expect(:get, fn "map:system:12345" -> nil end)
      |> expect(:put, fn "map:system:12345", _system_data -> :ok end)

      result = CacheHelpers.add_system_to_tracked("12345", %{name: "Test System"})
      assert result == :ok
    end

    test "handles adding duplicate system IDs" do
      RepositoryMock
      |> expect(:get_and_update, fn "tracked:systems", _fun -> {[], :already_tracked} end)
      |> expect(:put, fn "tracked:system:12345", true -> :ok end)
      |> expect(:get, fn "map:system:12345" -> %{"system_id" => "12345"} end)

      result = CacheHelpers.add_system_to_tracked(12_345, %{name: "Test System Updated"})
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
      RepositoryMock
      |> expect(:get_and_update, fn "tracked:characters", _fun -> {[], :added} end)
      |> expect(:put, fn "tracked:character:12345", true -> :ok end)
      |> expect(:get, fn "map:character:12345" -> nil end)
      |> expect(:put, fn "map:character:12345", _char_data -> :ok end)

      result = CacheHelpers.add_character_to_tracked(12_345, %{name: "Test Character"})
      assert result == :ok
    end

    test "adds character with string ID" do
      RepositoryMock
      |> expect(:get_and_update, fn "tracked:characters", _fun -> {[], :added} end)
      |> expect(:put, fn "tracked:character:12345", true -> :ok end)
      |> expect(:get, fn "map:character:12345" -> nil end)
      |> expect(:put, fn "map:character:12345", _char_data -> :ok end)

      result = CacheHelpers.add_character_to_tracked("12345", %{name: "Test Character"})
      assert result == :ok
    end

    test "handles adding duplicate character IDs" do
      RepositoryMock
      |> expect(:get_and_update, fn "tracked:characters", _fun -> {[], :already_tracked} end)
      |> expect(:put, fn "tracked:character:12345", true -> :ok end)
      |> expect(:get, fn "map:character:12345" -> %{"character_id" => "12345"} end)

      result = CacheHelpers.add_character_to_tracked(12_345, %{name: "Test Character Updated"})
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
