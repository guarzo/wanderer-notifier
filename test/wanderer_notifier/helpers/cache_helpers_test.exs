defmodule WandererNotifier.Helpers.CacheHelpersTest do
  use ExUnit.Case
  alias WandererNotifier.Helpers.CacheHelpers
  import ExUnit.CaptureLog

  # Basic sanity testing for public API
  describe "get_tracked_systems/0" do
    # Since we need the real CacheRepo to function properly,
    # we just test the function returns an empty list when not initialized
    test "returns empty list when called without context" do
      # Should return an empty list (doesn't error out)
      assert is_list(CacheHelpers.get_tracked_systems())
    end
  end

  describe "get_tracked_characters/0" do
    # Test the logging behavior as we can't rely on actual cache contents
    test "produces expected logs" do
      log =
        capture_log(fn ->
          assert is_list(CacheHelpers.get_tracked_characters())
        end)

      # In test environment with no cache, we expect errors
      assert log =~ "Cache error"
    end
  end

  # Add a few more basic sanity tests for the public API
  # that don't rely on actual cache contents
  describe "api functions" do
    test "add_system_to_tracked/2 returns :ok" do
      # We're not testing the actual functionality (would require cache)
      # but just that the function doesn't crash and returns expected value
      assert CacheHelpers.add_system_to_tracked("12345", "Test System") == :ok
    end

    test "remove_system_from_tracked/1 returns :ok" do
      # Just test that the function doesn't crash and returns expected value
      assert CacheHelpers.remove_system_from_tracked("12345") == :ok
    end

    test "add_character_to_tracked/2 returns :ok" do
      # Just test that the function doesn't crash and returns expected value
      assert CacheHelpers.add_character_to_tracked("12345", "Test Character") == :ok
    end

    test "remove_character_from_tracked/1 returns :ok" do
      # Just test that the function doesn't crash and returns expected value
      assert CacheHelpers.remove_character_from_tracked("12345") == :ok
    end
  end
end
