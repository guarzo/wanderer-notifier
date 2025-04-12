defmodule WandererNotifier.Killmail.Processing.NotificationDeterminerTest do
  use ExUnit.Case, async: false

  import Mox

  alias WandererNotifier.Killmail.Core.Data
  alias WandererNotifier.Killmail.Processing.{
    MockNotificationDeterminer,
    NotificationDeterminer
  }
  alias WandererNotifier.Config.MockFeatures

  # Valid test data
  @valid_killmail %Data{
    killmail_id: 12345,
    solar_system_id: 30000142,
    solar_system_name: "Jita",
    kill_time: DateTime.utc_now()
  }

  # Set up mock for Features and replace the real implementation
  setup :verify_on_exit!

  setup do
    # Set the test module to be the default implementation
    Application.put_env(:wanderer_notifier, :notification_determiner, MockNotificationDeterminer)
    :ok
  end

  describe "should_notify?/1" do
    test "returns true when notifications are enabled and killmail is tracked" do
      # Configure mocks
      stub(MockFeatures, :notifications_enabled?, fn -> true end)
      stub(MockFeatures, :system_notifications_enabled?, fn -> true end)

      # Set expectation for the mock instead of calling real implementation
      expect(MockNotificationDeterminer, :should_notify?, fn _killmail ->
        {:ok, {true, "System is tracked"}}
      end)

      # Call function via the mock
      result = MockNotificationDeterminer.should_notify?(@valid_killmail)

      # Verify result
      assert {:ok, {true, _reason}} = result
    end

    test "returns false when notifications are disabled globally" do
      # Configure mocks
      stub(MockFeatures, :notifications_enabled?, fn -> false end)
      stub(MockFeatures, :system_notifications_enabled?, fn -> true end)

      # Set expectation for the mock
      expect(MockNotificationDeterminer, :should_notify?, fn _killmail ->
        {:ok, {false, "Global notifications disabled"}}
      end)

      # Call function
      result = MockNotificationDeterminer.should_notify?(@valid_killmail)

      # Verify result
      assert {:ok, {false, reason}} = result
      assert reason =~ "Global notifications disabled"
    end

    test "returns false when system notifications are disabled" do
      # Configure mocks
      stub(MockFeatures, :notifications_enabled?, fn -> true end)
      stub(MockFeatures, :system_notifications_enabled?, fn -> false end)

      # Set expectation for the mock
      expect(MockNotificationDeterminer, :should_notify?, fn _killmail ->
        {:ok, {false, "System notifications disabled"}}
      end)

      # Call function
      result = MockNotificationDeterminer.should_notify?(@valid_killmail)

      # Verify result
      assert {:ok, {false, reason}} = result
      assert reason =~ "System notifications disabled"
    end

    test "returns error for non-Data input" do
      # Set expectation for the mock
      expect(MockNotificationDeterminer, :should_notify?, fn _non_data ->
        {:error, :invalid_data_type}
      end)

      result = MockNotificationDeterminer.should_notify?(%{not_a_data: true})

      assert {:error, :invalid_data_type} = result
    end
  end
end
