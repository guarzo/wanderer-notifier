defmodule WandererNotifier.Core.Application.ServiceTest do
  use ExUnit.Case, async: false
  import Mox

  alias WandererNotifier.Core.Application.Service
  alias WandererNotifier.MockDiscordNotifier, as: DiscordNotifier
  alias WandererNotifier.MockStructuredFormatter, as: StructuredFormatter

  setup :verify_on_exit!

  setup do
    # Set up default mock behaviors
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

    :ok
  end

  describe "startup notification" do
    test "sends startup notification successfully" do
      # Get the existing service PID or start a new one
      pid =
        case Process.whereis(Service) do
          nil ->
            {:ok, pid} = Service.start_link([])
            pid

          pid ->
            pid
        end

      # Send startup notification
      send(pid, :send_startup_notification)

      # Give it a moment to process
      Process.sleep(100)

      # The service should still be alive
      assert Process.alive?(pid)
    end
  end
end
