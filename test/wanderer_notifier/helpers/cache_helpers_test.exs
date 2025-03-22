defmodule WandererNotifier.Helpers.CacheHelpersTest do
  use ExUnit.Case, async: false
  require Logger
  alias WandererNotifier.Helpers.CacheHelpers
  import ExUnit.CaptureLog

  # Basic sanity testing for public API
  describe "get_tracked_systems/0" do
    test "returns empty list when no systems are tracked" do
      result = CacheHelpers.get_tracked_systems()
      assert is_list(result)
      assert result == []
    end

    test "produces expected logs" do
      log =
        capture_log(fn ->
          CacheHelpers.get_tracked_systems()
        end)

      assert log =~ "Cache error"
    end
  end

  describe "add_system_to_tracked/2" do
    test "adds system with integer ID" do
      result = CacheHelpers.add_system_to_tracked(12345, %{name: "Test System"})
      assert result == :ok
    end

    test "adds system with string ID" do
      result = CacheHelpers.add_system_to_tracked("12345", %{name: "Test System"})
      assert result == :ok
    end

    test "handles adding duplicate system IDs" do
      CacheHelpers.add_system_to_tracked(12345, %{name: "Test System"})
      result = CacheHelpers.add_system_to_tracked(12345, %{name: "Test System Updated"})
      assert result == :ok
    end
  end

  describe "remove_system_from_tracked/1" do
    test "removes system when it exists in tracked list" do
      # Add a system first
      CacheHelpers.add_system_to_tracked(12345, %{name: "Test System"})

      # Then remove it
      result = CacheHelpers.remove_system_from_tracked(12345)
      assert result == :ok
    end

    test "handles removing non-existent system gracefully" do
      result = CacheHelpers.remove_system_from_tracked(999_999)
      assert result == :ok
    end

    test "handles string ID for removal" do
      # Add with integer ID
      CacheHelpers.add_system_to_tracked(12345, %{name: "Test System"})

      # Remove with string ID
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

    test "produces expected logs" do
      log =
        capture_log(fn ->
          CacheHelpers.get_tracked_characters()
        end)

      assert log =~ "Cache error"
    end
  end

  describe "add_character_to_tracked/2" do
    test "adds character with integer ID" do
      result = CacheHelpers.add_character_to_tracked(12345, %{name: "Test Character"})
      assert result == :ok
    end

    test "adds character with string ID" do
      result = CacheHelpers.add_character_to_tracked("12345", %{name: "Test Character"})
      assert result == :ok
    end

    test "handles adding duplicate character IDs" do
      CacheHelpers.add_character_to_tracked(12345, %{name: "Test Character"})
      result = CacheHelpers.add_character_to_tracked(12345, %{name: "Test Character Updated"})
      assert result == :ok
    end
  end

  describe "remove_character_from_tracked/1" do
    test "removes character when it exists in tracked list" do
      # Add a character first
      CacheHelpers.add_character_to_tracked(12345, %{name: "Test Character"})

      # Then remove it
      result = CacheHelpers.remove_character_from_tracked(12345)
      assert result == :ok
    end

    test "handles removing non-existent character gracefully" do
      result = CacheHelpers.remove_character_from_tracked(999_999)
      assert result == :ok
    end

    test "handles string ID for removal" do
      # Add with integer ID
      CacheHelpers.add_character_to_tracked(12345, %{name: "Test Character"})

      # Remove with string ID
      result = CacheHelpers.remove_character_from_tracked("12345")
      assert result == :ok
    end
  end
end
