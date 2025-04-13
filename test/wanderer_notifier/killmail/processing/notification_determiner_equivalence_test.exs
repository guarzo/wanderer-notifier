defmodule WandererNotifier.Killmail.Processing.NotificationDeterminerEquivalenceTest do
  use ExUnit.Case, async: false
  import Mox

  alias WandererNotifier.Killmail.Core.Data, as: KillmailData
  alias WandererNotifier.KillmailProcessing.KillmailData, as: OldKillmailData
  alias WandererNotifier.Killmail.Processing.NotificationDeterminer, as: NewDeterminer
  alias WandererNotifier.Processing.Killmail.NotificationDeterminer, as: OldDeterminer

  alias WandererNotifier.Config.MockFeatures
  alias WandererNotifier.MockRepository
  alias WandererNotifier.MockCacheHelpers

  # Setup test data
  @system_id 30_000_142
  @killmail_id 12345

  # Standard test killmail with matched fields for both old and new formats
  @shared_killmail_attrs %{
    killmail_id: @killmail_id,
    solar_system_id: @system_id,
    solar_system_name: "Jita",
    kill_time: DateTime.utc_now(),
    victim_id: 98765,
    victim_name: "Test Victim",
    victim_corporation_id: 123_456,
    victim_corporation_name: "Test Corp",
    victim_alliance_id: 789_012,
    victim_alliance_name: "Test Alliance",
    victim_ship_id: 587,
    victim_ship_name: "Rifter",
    raw_zkb_data: %{
      "totalValue" => 1_000_000.0
    }
  }

  setup :verify_on_exit!

  setup do
    # Configure common mocks
    stub(MockFeatures, :notifications_enabled?, fn -> true end)
    stub(MockFeatures, :system_notifications_enabled?, fn -> true end)

    # Default cache behavior - system is tracked
    stub(MockCacheHelpers, :is_system_tracked?, fn _ -> true end)

    # Default repository behavior - killmail doesn't exist yet
    stub(MockRepository, :check_killmail_exists_in_database, fn _ -> false end)

    :ok
  end

  describe "equivalence tests" do
    test "both implementations return the same result for tracked system" do
      # Create both killmail formats
      old_killmail = struct(OldKillmailData, @shared_killmail_attrs)
      new_killmail = struct(KillmailData, @shared_killmail_attrs)

      # Both implementations should return the system is tracked
      old_result = OldDeterminer.should_notify?(old_killmail)
      new_result = NewDeterminer.should_notify?(new_killmail)

      # Compare results - both should indicate notification should happen
      assert {:ok, {old_should_notify, old_reason}} = old_result
      assert {:ok, {new_should_notify, new_reason}} = new_result

      assert old_should_notify == new_should_notify
      assert old_should_notify == true
      assert old_reason =~ "System"
      assert new_reason =~ "System"
    end

    test "both implementations respect global notification settings" do
      # Configure mocks - disable notifications
      stub(MockFeatures, :notifications_enabled?, fn -> false end)

      # Create both killmail formats
      old_killmail = struct(OldKillmailData, @shared_killmail_attrs)
      new_killmail = struct(KillmailData, @shared_killmail_attrs)

      # Both implementations should return notifications disabled
      old_result = OldDeterminer.should_notify?(old_killmail)
      new_result = NewDeterminer.should_notify?(new_killmail)

      # Compare results - both should indicate no notification
      assert {:ok, {old_should_notify, old_reason}} = old_result
      assert {:ok, {new_should_notify, new_reason}} = new_result

      assert old_should_notify == new_should_notify
      assert old_should_notify == false
      assert old_reason =~ "disabled"
      assert new_reason =~ "disabled"
    end

    test "both implementations respect system notification settings" do
      # Configure mocks - disable system notifications
      stub(MockFeatures, :system_notifications_enabled?, fn -> false end)

      # Create both killmail formats
      old_killmail = struct(OldKillmailData, @shared_killmail_attrs)
      new_killmail = struct(KillmailData, @shared_killmail_attrs)

      # Both implementations should return system notifications disabled
      old_result = OldDeterminer.should_notify?(old_killmail)
      new_result = NewDeterminer.should_notify?(new_killmail)

      # Compare results - both should indicate no notification
      assert {:ok, {old_should_notify, old_reason}} = old_result
      assert {:ok, {new_should_notify, new_reason}} = new_result

      assert old_should_notify == new_should_notify
      assert old_should_notify == false
      assert old_reason =~ "System notifications disabled"
      assert new_reason =~ "System notifications disabled"
    end

    test "both implementations handle untracked systems the same" do
      # Configure mocks - system is not tracked
      stub(MockCacheHelpers, :is_system_tracked?, fn _ -> false end)

      # Create both killmail formats
      old_killmail = struct(OldKillmailData, @shared_killmail_attrs)
      new_killmail = struct(KillmailData, @shared_killmail_attrs)

      # Call both implementations
      old_result = OldDeterminer.should_notify?(old_killmail)
      new_result = NewDeterminer.should_notify?(new_killmail)

      # Compare results - both should indicate no notification
      assert {:ok, {old_should_notify, old_reason}} = old_result
      assert {:ok, {new_should_notify, new_reason}} = new_result

      assert old_should_notify == new_should_notify
      assert old_should_notify == false
      assert old_reason =~ "Not tracked"
      assert new_reason =~ "Not tracked"
    end

    test "both implementations handle duplicate killmails the same" do
      # Configure mocks - system is tracked but killmail exists (is duplicate)
      stub(MockCacheHelpers, :is_system_tracked?, fn _ -> true end)
      stub(MockRepository, :check_killmail_exists_in_database, fn _ -> true end)

      # Create both killmail formats
      old_killmail = struct(OldKillmailData, @shared_killmail_attrs)
      new_killmail = struct(KillmailData, @shared_killmail_attrs)

      # Call both implementations
      old_result = OldDeterminer.should_notify?(old_killmail)
      new_result = NewDeterminer.should_notify?(new_killmail)

      # Compare results - both should indicate no notification due to duplication
      assert {:ok, {old_should_notify, old_reason}} = old_result
      assert {:ok, {new_should_notify, new_reason}} = new_result

      assert old_should_notify == new_should_notify
      assert old_should_notify == false
      assert old_reason =~ "Duplicate" or old_reason =~ "already processed"
      assert new_reason =~ "Duplicate" or new_reason =~ "already processed"
    end

    test "both implementations reject invalid input types the same" do
      # Pass invalid data type (not a KillmailData struct)
      invalid_data = %{not_a_killmail: true}

      # Call both implementations
      old_result = OldDeterminer.should_notify?(invalid_data)
      new_result = NewDeterminer.should_notify?(invalid_data)

      # Both should return an error for invalid input
      assert {:error, _} = old_result
      assert {:error, _} = new_result
    end
  end
end
