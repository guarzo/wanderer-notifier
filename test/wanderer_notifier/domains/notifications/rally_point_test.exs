defmodule WandererNotifier.Domains.Notifications.RallyPointTest do
  use ExUnit.Case, async: true
  import Mox

  alias WandererNotifier.Domains.Notifications.Determiner
  alias WandererNotifier.Domains.Notifications.Formatters.NotificationFormatter
  alias WandererNotifier.Domains.Notifications.Notifiers.Discord.Notifier
  alias WandererNotifier.Map.EventProcessor
  alias WandererNotifier.RallyPointFixtures
  alias WandererNotifier.Shared.Config

  setup :verify_on_exit!

  describe "Rally Point Event Processing" do
    test "processes rally_point_added event correctly" do
      event = RallyPointFixtures.rally_point_event()

      # Mock the notification service call
      expect(WandererNotifier.Domains.Notifications.MockNotificationService, :notify, fn
        :rally_point, rally_data ->
          assert rally_data.id == "550e8400-e29b-41d4-a716-446655440000"
          assert rally_data.system_name == "Jita"
          assert rally_data.character_name == "Test Pilot"
          assert rally_data.message == "Form up for fleet ops!"
          :ok
      end)

      # Replace the notification service with our mock for this test
      original_module =
        Application.get_env(
          :wanderer_notifier,
          :notification_service_module,
          WandererNotifier.Domains.Notifications.NotificationService
        )

      Application.put_env(
        :wanderer_notifier,
        :notification_service_module,
        WandererNotifier.Domains.Notifications.MockNotificationService
      )

      try do
        result = EventProcessor.process_event(event, "test-map")
        assert result == :ok
      after
        Application.put_env(:wanderer_notifier, :notification_service_module, original_module)
      end
    end

    test "categorizes rally_point_added event as :rally" do
      # Test the private categorize_event function through the public process_event
      event = RallyPointFixtures.rally_point_event()

      # This should not raise an error and should process as a rally event
      # Mock the notification to prevent actual sending
      expect(WandererNotifier.Domains.Notifications.MockNotificationService, :notify, fn
        :rally_point, _rally_data -> :ok
      end)

      original_module = Application.get_env(:wanderer_notifier, :notification_service_module)

      Application.put_env(
        :wanderer_notifier,
        :notification_service_module,
        WandererNotifier.Domains.Notifications.MockNotificationService
      )

      try do
        result = EventProcessor.process_event(event, "test-map")
        assert result == :ok
      after
        Application.put_env(:wanderer_notifier, :notification_service_module, original_module)
      end
    end
  end

  describe "Rally Point Determiner" do
    test "should_notify? returns true when rally notifications enabled and not duplicate" do
      # Mock config to enable rally notifications
      Application.put_env(:wanderer_notifier, :rally_notifications_enabled, true)

      # Mock deduplication to return :new
      expect(WandererNotifier.Domains.Notifications.MockDeduplication, :check, fn
        :rally_point, "test-rally-id" -> {:ok, :new}
      end)

      # Replace deduplication module temporarily
      original_dedup = Application.get_env(:wanderer_notifier, :deduplication_module)

      Application.put_env(
        :wanderer_notifier,
        :deduplication_module,
        WandererNotifier.Domains.Notifications.MockDeduplication
      )

      try do
        result = Determiner.should_notify?(:rally_point, "test-rally-id", %{})
        assert result == true
      after
        Application.put_env(:wanderer_notifier, :deduplication_module, original_dedup)
      end
    end

    test "should_notify? returns false when rally notifications disabled" do
      # Mock config to disable rally notifications
      Application.put_env(:wanderer_notifier, :rally_notifications_enabled, false)

      result = Determiner.should_notify?(:rally_point, "test-rally-id", %{})
      assert result == false
    end

    test "should_notify? returns false for duplicate rally points" do
      # Mock config to enable rally notifications
      Application.put_env(:wanderer_notifier, :rally_notifications_enabled, true)

      # Mock deduplication to return :duplicate
      expect(WandererNotifier.Domains.Notifications.MockDeduplication, :check, fn
        :rally_point, "test-rally-id" -> {:ok, :duplicate}
      end)

      # Replace deduplication module temporarily
      original_dedup = Application.get_env(:wanderer_notifier, :deduplication_module)

      Application.put_env(
        :wanderer_notifier,
        :deduplication_module,
        WandererNotifier.Domains.Notifications.MockDeduplication
      )

      try do
        result = Determiner.should_notify?(:rally_point, "test-rally-id", %{})
        assert result == false
      after
        Application.put_env(:wanderer_notifier, :deduplication_module, original_dedup)
      end
    end
  end

  describe "Rally Point Formatter" do
    test "formats rally point notification correctly" do
      rally_data = RallyPointFixtures.rally_point_data()
      expected = RallyPointFixtures.expected_notification_format()

      result = NotificationFormatter.format_notification(rally_data)

      # Compare all fields except timestamp which is dynamic
      assert result.type == expected.type
      assert result.title == expected.title
      assert result.description == expected.description
      assert result.color == expected.color
      assert result.fields == expected.fields
      assert result.footer == expected.footer
      assert Map.has_key?(result, :timestamp)
    end

    test "formats rally point notification with no message" do
      rally_data = RallyPointFixtures.rally_point_data(%{message: nil})
      expected = RallyPointFixtures.expected_notification_format_no_message()

      result = NotificationFormatter.format_notification(rally_data)

      # Check that the message field shows "No message provided"
      message_field = Enum.find(result.fields, fn field -> field.name == "Message" end)
      assert message_field.value == "No message provided"
    end
  end

  describe "Rally Point Discord Notifier" do
    test "sends rally point notification to correct channel" do
      rally_data = RallyPointFixtures.rally_point_data()

      # Mock config for rally channel
      Application.put_env(:wanderer_notifier, :discord_rally_channel_id, "123456789")
      Application.put_env(:wanderer_notifier, :discord_rally_group_id, "987654321")

      # Mock the NeoClient
      expect(
        WandererNotifier.Domains.Notifications.Notifiers.Discord.MockNeoClient,
        :send_embed,
        fn
          notification, channel_id ->
            assert channel_id == "123456789"
            assert notification.content == "<@&987654321> Rally point created!"
            assert notification.type == :rally_point
            {:ok, "message_id"}
        end
      )

      # Replace NeoClient temporarily
      original_client = Application.get_env(:wanderer_notifier, :neo_client_module)

      Application.put_env(
        :wanderer_notifier,
        :neo_client_module,
        WandererNotifier.Domains.Notifications.Notifiers.Discord.MockNeoClient
      )

      try do
        result = Notifier.send_rally_point_notification(rally_data)
        assert result == {:ok, :sent}
      after
        Application.put_env(:wanderer_notifier, :neo_client_module, original_client)
      end
    end

    test "sends rally point notification without group ping when group_id not configured" do
      rally_data = RallyPointFixtures.rally_point_data()

      # Mock config without group ID
      Application.put_env(:wanderer_notifier, :discord_rally_channel_id, "123456789")
      Application.put_env(:wanderer_notifier, :discord_rally_group_id, nil)

      # Mock the NeoClient
      expect(
        WandererNotifier.Domains.Notifications.Notifiers.Discord.MockNeoClient,
        :send_embed,
        fn
          notification, channel_id ->
            assert channel_id == "123456789"
            assert notification.content == "Rally point created!"
            {:ok, "message_id"}
        end
      )

      # Replace NeoClient temporarily
      original_client = Application.get_env(:wanderer_notifier, :neo_client_module)

      Application.put_env(
        :wanderer_notifier,
        :neo_client_module,
        WandererNotifier.Domains.Notifications.Notifiers.Discord.MockNeoClient
      )

      try do
        result = Notifier.send_rally_point_notification(rally_data)
        assert result == {:ok, :sent}
      after
        Application.put_env(:wanderer_notifier, :neo_client_module, original_client)
      end
    end

    test "falls back to default channel when rally channel not configured" do
      rally_data = RallyPointFixtures.rally_point_data()

      # Mock config without rally channel (should fallback)
      Application.put_env(:wanderer_notifier, :discord_rally_channel_id, nil)
      Application.put_env(:wanderer_notifier, :discord_channel_id, "default_channel")

      # Mock the NeoClient
      expect(
        WandererNotifier.Domains.Notifications.Notifiers.Discord.MockNeoClient,
        :send_embed,
        fn
          notification, channel_id ->
            assert channel_id == "default_channel"
            {:ok, "message_id"}
        end
      )

      # Replace NeoClient temporarily
      original_client = Application.get_env(:wanderer_notifier, :neo_client_module)

      Application.put_env(
        :wanderer_notifier,
        :neo_client_module,
        WandererNotifier.Domains.Notifications.Notifiers.Discord.MockNeoClient
      )

      try do
        result = Notifier.send_rally_point_notification(rally_data)
        assert result == {:ok, :sent}
      after
        Application.put_env(:wanderer_notifier, :neo_client_module, original_client)
      end
    end
  end

  describe "Configuration" do
    test "rally_notifications_enabled? returns correct values" do
      # Test default value
      Application.put_env(:wanderer_notifier, :rally_notifications_enabled, true)
      assert Config.rally_notifications_enabled?() == true

      Application.put_env(:wanderer_notifier, :rally_notifications_enabled, false)
      assert Config.rally_notifications_enabled?() == false
    end

    test "discord_rally_channel_id falls back to default channel" do
      Application.put_env(:wanderer_notifier, :discord_rally_channel_id, nil)
      Application.put_env(:wanderer_notifier, :discord_channel_id, "default_channel")

      assert Config.discord_rally_channel_id() == "default_channel"

      Application.put_env(:wanderer_notifier, :discord_rally_channel_id, "rally_channel")
      assert Config.discord_rally_channel_id() == "rally_channel"
    end

    test "discord_rally_group_id returns configured value" do
      Application.put_env(:wanderer_notifier, :discord_rally_group_id, "test_group")
      assert Config.discord_rally_group_id() == "test_group"

      Application.put_env(:wanderer_notifier, :discord_rally_group_id, nil)
      assert Config.discord_rally_group_id() == nil
    end
  end
end
