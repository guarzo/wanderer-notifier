defmodule WandererNotifier.Helpers.DeduplicationHelperTest do
  use ExUnit.Case, async: false
  alias WandererNotifier.Helpers.DeduplicationHelper

  setup do
    # Start with a different registered name to avoid conflicts
    Process.flag(:trap_exit, true)

    # Only try to start if it's not already started
    if Process.whereis(DeduplicationHelper) == nil do
      {:ok, _pid} = DeduplicationHelper.start_link([])
    end

    # Clear all deduplication entries before each test
    DeduplicationHelper.clear_all()
    :ok
  end

  describe "check_and_mark/1" do
    test "returns new for first call with a key" do
      assert {:ok, :new} = DeduplicationHelper.check_and_mark("test:key1")
    end

    test "returns duplicate for second call with the same key" do
      assert {:ok, :new} = DeduplicationHelper.check_and_mark("test:key2")
      assert {:ok, :duplicate} = DeduplicationHelper.check_and_mark("test:key2")
    end

    test "different keys are tracked separately" do
      assert {:ok, :new} = DeduplicationHelper.check_and_mark("test:key3")
      assert {:ok, :new} = DeduplicationHelper.check_and_mark("test:key4")
      assert {:ok, :duplicate} = DeduplicationHelper.check_and_mark("test:key3")
    end

    @tag :ttl_test
    test "entries expire after TTL" do
      # Mock a short TTL for the test by sending a manual expiration message
      test_key = "test:ttl_expire"
      assert {:ok, :new} = DeduplicationHelper.check_and_mark(test_key)
      assert {:ok, :duplicate} = DeduplicationHelper.check_and_mark(test_key)

      # Manually trigger expiration
      send(DeduplicationHelper, {:clear_dedup_key, test_key})

      # Small delay to allow processing
      Process.sleep(100)

      # Should be treated as new again after expiration
      assert {:ok, :new} = DeduplicationHelper.check_and_mark(test_key)
    end
  end

  describe "check_and_mark_system/1" do
    test "handles integer system IDs" do
      system_id = 31_000_001
      assert {:ok, :new} = DeduplicationHelper.check_and_mark_system(system_id)
      assert {:ok, :duplicate} = DeduplicationHelper.check_and_mark_system(system_id)
    end

    test "handles string system IDs" do
      system_id = "31_000_002"
      assert {:ok, :new} = DeduplicationHelper.check_and_mark_system(system_id)
      assert {:ok, :duplicate} = DeduplicationHelper.check_and_mark_system(system_id)
    end

    test "different system IDs are tracked separately" do
      assert {:ok, :new} = DeduplicationHelper.check_and_mark_system(31_000_003)
      assert {:ok, :new} = DeduplicationHelper.check_and_mark_system(31_000_004)
      assert {:ok, :duplicate} = DeduplicationHelper.check_and_mark_system(31_000_003)
    end
  end

  describe "check_and_mark_character/1" do
    test "handles integer character IDs" do
      character_id = 12_345
      assert {:ok, :new} = DeduplicationHelper.check_and_mark_character(character_id)
      assert {:ok, :duplicate} = DeduplicationHelper.check_and_mark_character(character_id)
    end

    test "handles string character IDs" do
      character_id = "67890"
      assert {:ok, :new} = DeduplicationHelper.check_and_mark_character(character_id)
      assert {:ok, :duplicate} = DeduplicationHelper.check_and_mark_character(character_id)
    end
  end

  describe "check_and_mark_kill/1" do
    test "handles integer kill IDs" do
      kill_id = 123_456_789
      assert {:ok, :new} = DeduplicationHelper.check_and_mark_kill(kill_id)
      assert {:ok, :duplicate} = DeduplicationHelper.check_and_mark_kill(kill_id)
    end

    test "handles string kill IDs" do
      kill_id = "987_654_321"
      assert {:ok, :new} = DeduplicationHelper.check_and_mark_kill(kill_id)
      assert {:ok, :duplicate} = DeduplicationHelper.check_and_mark_kill(kill_id)
    end
  end

  describe "clear_all/0" do
    test "clears all deduplication entries" do
      # Mark some entries
      DeduplicationHelper.check_and_mark("test:clear1")
      DeduplicationHelper.check_and_mark_system(30_000_142)
      DeduplicationHelper.check_and_mark_character(12_345)
      DeduplicationHelper.check_and_mark_kill(123_456_789)

      # They should all be duplicates
      assert {:ok, :duplicate} = DeduplicationHelper.check_and_mark("test:clear1")
      assert {:ok, :duplicate} = DeduplicationHelper.check_and_mark_system(30_000_142)
      assert {:ok, :duplicate} = DeduplicationHelper.check_and_mark_character(12_345)
      assert {:ok, :duplicate} = DeduplicationHelper.check_and_mark_kill(123_456_789)

      # Clear all entries
      :ok = DeduplicationHelper.clear_all()

      # Now they should all be new again
      assert {:ok, :new} = DeduplicationHelper.check_and_mark("test:clear1")
      assert {:ok, :new} = DeduplicationHelper.check_and_mark_system(30_000_142)
      assert {:ok, :new} = DeduplicationHelper.check_and_mark_character(12_345)
      assert {:ok, :new} = DeduplicationHelper.check_and_mark_kill(123_456_789)
    end
  end

  describe "handle_clear_key/1" do
    test "clears a specific key" do
      # Mark a key
      assert {:ok, :new} = DeduplicationHelper.check_and_mark("test:expire")
      assert {:ok, :duplicate} = DeduplicationHelper.check_and_mark("test:expire")

      # Manually clear the key
      :ok = DeduplicationHelper.handle_clear_key("test:expire")

      # It should be new again
      assert {:ok, :new} = DeduplicationHelper.check_and_mark("test:expire")
    end
  end

  describe "TTL and expiration" do
    test "entries can be manually expired" do
      test_key = "test:manual_expire"

      # Mark the key
      assert {:ok, :new} = DeduplicationHelper.check_and_mark(test_key)
      assert {:ok, :duplicate} = DeduplicationHelper.check_and_mark(test_key)

      # Manually clear the key
      :ok = DeduplicationHelper.handle_clear_key(test_key)

      # Should be new again
      assert {:ok, :new} = DeduplicationHelper.check_and_mark(test_key)
    end

    test "clearing all entries removes all deduplication data" do
      keys = ["test:clear1", "test:clear2", "test:clear3"]

      # Mark all keys
      Enum.each(keys, fn key ->
        assert {:ok, :new} = DeduplicationHelper.check_and_mark(key)
      end)

      # Verify they're all marked
      Enum.each(keys, fn key ->
        assert {:ok, :duplicate} = DeduplicationHelper.check_and_mark(key)
      end)

      # Clear all entries
      :ok = DeduplicationHelper.clear_all()

      # Verify they're all new again
      Enum.each(keys, fn key ->
        assert {:ok, :new} = DeduplicationHelper.check_and_mark(key)
      end)
    end
  end
end
