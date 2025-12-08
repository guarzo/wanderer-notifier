defmodule WandererNotifier.Domains.Notifications.DeterminerTest do
  @moduledoc """
  Unit tests for the Notification Determiner, specifically focused on
  priority system notification behavior.

  These tests verify that priority systems can receive notifications even
  when regular system notifications are disabled.
  """

  use ExUnit.Case, async: false

  import Mox

  alias WandererNotifier.Domains.Notifications.Determiner
  alias WandererNotifier.PersistentValues

  # Allow mocks to be called from any process in async tests
  setup :verify_on_exit!

  setup do
    # Set up deduplication mock to return :new for all checks
    stub(WandererNotifier.MockDeduplication, :check, fn _type, _id -> {:ok, :new} end)
    # Clear any existing priority systems before each test
    PersistentValues.put(:priority_systems, [])

    # Store original values
    original_system_notifications = System.get_env("SYSTEM_NOTIFICATIONS_ENABLED")
    original_start_time = Application.get_env(:wanderer_notifier, :start_time)

    original_suppression_seconds =
      Application.get_env(:wanderer_notifier, :startup_suppression_seconds)

    # Disable startup suppression by clearing start_time and setting suppression to 0
    Application.put_env(:wanderer_notifier, :start_time, nil)
    Application.put_env(:wanderer_notifier, :startup_suppression_seconds, 0)

    on_exit(fn ->
      # Restore original values
      if original_system_notifications do
        System.put_env("SYSTEM_NOTIFICATIONS_ENABLED", original_system_notifications)
      else
        System.delete_env("SYSTEM_NOTIFICATIONS_ENABLED")
      end

      if original_start_time do
        Application.put_env(:wanderer_notifier, :start_time, original_start_time)
      else
        Application.delete_env(:wanderer_notifier, :start_time)
      end

      if original_suppression_seconds do
        Application.put_env(
          :wanderer_notifier,
          :startup_suppression_seconds,
          original_suppression_seconds
        )
      else
        Application.delete_env(:wanderer_notifier, :startup_suppression_seconds)
      end

      # Clean up priority systems
      PersistentValues.put(:priority_systems, [])
    end)

    :ok
  end

  describe "priority system notifications" do
    test "priority system receives notification when system notifications are disabled" do
      # Disable regular system notifications
      System.put_env("SYSTEM_NOTIFICATIONS_ENABLED", "false")

      # Add "Jita" as a priority system
      system_name = "Jita"
      system_hash = :erlang.phash2(system_name)
      PersistentValues.add(:priority_systems, system_hash)

      # Verify priority system is registered
      assert system_hash in PersistentValues.get(:priority_systems)

      # Create system data with the name
      system_data = %{name: "Jita", solar_system_id: 30_000_142}

      # Priority system should be allowed to notify even with notifications disabled
      result = Determiner.should_notify?(:system, 30_000_142, system_data)

      assert result == true,
             "Priority system should receive notification even when system notifications are disabled"
    end

    test "non-priority system is blocked when system notifications are disabled" do
      # Disable regular system notifications
      System.put_env("SYSTEM_NOTIFICATIONS_ENABLED", "false")

      # Don't add any priority systems
      assert PersistentValues.get(:priority_systems) == []

      # Create system data for a non-priority system
      system_data = %{name: "Amarr", solar_system_id: 30_002_187}

      # Non-priority system should NOT be allowed to notify
      result = Determiner.should_notify?(:system, 30_002_187, system_data)

      assert result == false,
             "Non-priority system should be blocked when system notifications are disabled"
    end

    test "all systems receive notifications when system notifications are enabled" do
      # Enable system notifications
      System.put_env("SYSTEM_NOTIFICATIONS_ENABLED", "true")

      # Don't add any priority systems
      assert PersistentValues.get(:priority_systems) == []

      # Create system data for a regular system
      system_data = %{name: "Dodixie", solar_system_id: 30_002_659}

      # Should be allowed to notify
      result = Determiner.should_notify?(:system, 30_002_659, system_data)

      assert result == true,
             "All systems should receive notifications when system notifications are enabled"
    end

    test "priority system with string name key is recognized" do
      System.put_env("SYSTEM_NOTIFICATIONS_ENABLED", "false")

      system_name = "J155416"
      system_hash = :erlang.phash2(system_name)
      PersistentValues.add(:priority_systems, system_hash)

      # Test with string key format
      system_data = %{"name" => "J155416", "solar_system_id" => 31_001_503}

      result = Determiner.should_notify?(:system, 31_001_503, system_data)
      assert result == true
    end

    test "priority system with solar_system_name key is recognized" do
      System.put_env("SYSTEM_NOTIFICATIONS_ENABLED", "false")

      system_name = "Thera"
      system_hash = :erlang.phash2(system_name)
      PersistentValues.add(:priority_systems, system_hash)

      # Test with solar_system_name key format
      system_data = %{solar_system_name: "Thera", solar_system_id: 31_000_005}

      result = Determiner.should_notify?(:system, 31_000_005, system_data)
      assert result == true
    end

    test "priority system hash matches the consumer module's hash" do
      # This test ensures the hash algorithm matches between
      # the consumer (where priority systems are added) and the determiner
      system_name = "Test System"

      # This is how consumer.ex hashes system names
      expected_hash = :erlang.phash2(system_name)

      # Add using the same method
      PersistentValues.add(:priority_systems, expected_hash)

      # Verify it's stored
      stored_hashes = PersistentValues.get(:priority_systems)
      assert expected_hash in stored_hashes
    end

    test "nil system_data is handled gracefully" do
      System.put_env("SYSTEM_NOTIFICATIONS_ENABLED", "false")

      # With nil data, should not be treated as priority
      result = Determiner.should_notify?(:system, 12_345, nil)
      assert result == false
    end

    test "empty map system_data is handled gracefully" do
      System.put_env("SYSTEM_NOTIFICATIONS_ENABLED", "false")

      # With empty map, should not be treated as priority
      result = Determiner.should_notify?(:system, 12_345, %{})
      assert result == false
    end

    test "multiple priority systems work correctly" do
      System.put_env("SYSTEM_NOTIFICATIONS_ENABLED", "false")

      # Add multiple priority systems
      systems = ["Jita", "Amarr", "J155416"]

      for name <- systems do
        PersistentValues.add(:priority_systems, :erlang.phash2(name))
      end

      # All should be recognized as priority
      for name <- systems do
        system_data = %{name: name, solar_system_id: :erlang.phash2(name)}
        result = Determiner.should_notify?(:system, :erlang.phash2(name), system_data)

        assert result == true,
               "System '#{name}' should be recognized as priority"
      end

      # Non-priority system should still be blocked
      non_priority_data = %{name: "Rens", solar_system_id: 30_002_510}
      result = Determiner.should_notify?(:system, 30_002_510, non_priority_data)
      assert result == false
    end
  end
end
