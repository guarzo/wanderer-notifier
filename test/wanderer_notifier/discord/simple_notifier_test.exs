defmodule WandererNotifier.Discord.SimpleNotifierTest do
  use ExUnit.Case

  describe "Discord notifications in test mode" do
    setup do
      # Ensure we're in test mode
      Application.put_env(:wanderer_notifier, :env, :test)
      # Configure for tests
      Application.put_env(:wanderer_notifier, :discord_channel_id, "test_channel_id")
      Application.put_env(:wanderer_notifier, :discord_bot_token, "test_bot_token")
      :ok
    end

    test "send_message returns :ok in test environment" do
      result = WandererNotifier.Discord.Notifier.send_message("Test message")
      assert result == :ok
    end

    test "send_embed returns :ok in test environment" do
      result = WandererNotifier.Discord.Notifier.send_embed("Test Title", "Test Description")
      assert result == :ok
    end
  end
end
