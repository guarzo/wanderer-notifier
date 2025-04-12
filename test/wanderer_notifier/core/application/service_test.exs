defmodule WandererNotifier.Core.Application.ServiceTest do
  use ExUnit.Case, async: false
  import Mox

  alias WandererNotifier.Core.Application.Service
  alias WandererNotifier.MockDiscordNotifier, as: DiscordNotifier
  alias WandererNotifier.MockStructuredFormatter, as: StructuredFormatter
  alias WandererNotifier.Config.MockFeatures

  setup :verify_on_exit!

  setup do
    # Set up default mock behaviors for Config
    stub(WandererNotifier.MockConfig, :get_feature_status, fn ->
      %{
        activity_charts: true,
        kill_charts: true,
        map_charts: true,
        character_notifications_enabled: true,
        system_notifications_enabled: true,
        character_tracking_enabled: true,
        system_tracking_enabled: true,
        tracked_systems_notifications_enabled: true,
        tracked_characters_notifications_enabled: true,
        kill_notifications_enabled: true,
        notifications_enabled: true
      }
    end)

    # Set up MockFeatures to allow calls from any process
    Mox.allow(MockFeatures, self(), :_)

    # Add stub for MockFeatures to handle any calls from any processes
    stub(MockFeatures, :status_messages_disabled?, fn -> false end)

    stub(MockFeatures, :get_feature, fn
      :status_messages_disabled, false -> false
      key, default -> default
    end)

    stub(MockFeatures, :notifications_enabled?, fn -> true end)

    stub(MockFeatures, :get_env, fn
      :features, _default -> %{status_messages_disabled: false}
      _key, default -> default
    end)

    # Mock the structured formatter
    stub(StructuredFormatter, :format_system_status_message, fn _title,
                                                                _desc,
                                                                _stats,
                                                                _uptime,
                                                                _features,
                                                                _license,
                                                                _systems,
                                                                _chars ->
      %{content: "Test message"}
    end)

    stub(StructuredFormatter, :to_discord_format, fn _message ->
      %{content: "Test message"}
    end)

    # Mock Discord notifier
    stub(DiscordNotifier, :send_discord_embed, fn _embed ->
      {:ok, %{status_code: 200}}
    end)

    stub(DiscordNotifier, :send_notification, fn _type, _data ->
      {:ok, %{status_code: 200}}
    end)

    # Allow these mocks to be used from any processes
    Mox.allow(StructuredFormatter, self(), :_)
    Mox.allow(DiscordNotifier, self(), :_)

    # Setup for notification channel mocking
    stub(WandererNotifier.Config.NotificationsMock, :channel_id, fn _type -> "123456789" end)
    Mox.allow(WandererNotifier.Config.NotificationsMock, self(), :_)

    # Mock NotifierFactory
    stub(WandererNotifier.MockNotifierFactory, :notify, fn _type, _args -> {:ok, %{}} end)
    Mox.allow(WandererNotifier.MockNotifierFactory, self(), :_)

    :ok
  end

  describe "startup notification" do
    test "sends startup notification successfully" do
      # Make sure there's no existing process
      case Process.whereis(Service) do
        nil -> :ok
        pid -> Process.exit(pid, :normal)
      end

      # Start the service in test mode
      {:ok, pid} = Service.start_link([])

      # Wait a moment to ensure it's fully started
      Process.sleep(100)

      # Send startup notification
      send(pid, :send_startup_notification)

      # Give it time to process
      Process.sleep(200)

      # The service should still be alive
      assert Process.alive?(pid)

      # Clean up
      Process.exit(pid, :normal)
      Process.sleep(50)
    end
  end
end
