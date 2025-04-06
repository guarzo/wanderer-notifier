defmodule WandererNotifier.Config.NotificationsTest do
  use ExUnit.Case, async: true

  alias WandererNotifier.Config.Notifications

  describe "channels" do
    test "should return system_kill channel ID" do
      # Mock the environment variable
      Application.put_env(:wanderer_notifier, :discord_system_kill_channel_id, "12345")

      # Test the function
      assert Notifications.channel_id(:system_kill) == "12345"

      # Clean up
      Application.delete_env(:wanderer_notifier, :discord_system_kill_channel_id)
    end

    test "should return character_kill channel ID" do
      # Mock the environment variable
      Application.put_env(:wanderer_notifier, :discord_character_kill_channel_id, "67890")

      # Test the function
      assert Notifications.channel_id(:character_kill) == "67890"

      # Clean up
      Application.delete_env(:wanderer_notifier, :discord_character_kill_channel_id)
    end

    test "should use fallback for missing channel IDs" do
      # Setup main channel as fallback
      Application.put_env(:wanderer_notifier, :discord_channel_id, "main-channel")

      # Test fallback for system kill channel
      assert Notifications.channel_id(:system_kill) == "main-channel"

      # Test fallback for character kill channel
      assert Notifications.channel_id(:character_kill) == "main-channel"

      # Clean up
      Application.delete_env(:wanderer_notifier, :discord_channel_id)
    end
  end

  describe "get_discord_channel_id_for" do
    test "should map kill feature to system_kill channel" do
      # Mock the environment variable
      Application.put_env(:wanderer_notifier, :discord_system_kill_channel_id, "12345")

      # Test the mapping
      assert Notifications.get_discord_channel_id_for(:kill) == "12345"

      # Clean up
      Application.delete_env(:wanderer_notifier, :discord_system_kill_channel_id)
    end

    test "should return appropriate channel for system_kill" do
      # Mock the environment variable
      Application.put_env(:wanderer_notifier, :discord_system_kill_channel_id, "12345")

      # Test the function
      assert Notifications.get_discord_channel_id_for(:system_kill) == "12345"

      # Clean up
      Application.delete_env(:wanderer_notifier, :discord_system_kill_channel_id)
    end

    test "should return appropriate channel for character_kill" do
      # Mock the environment variable
      Application.put_env(:wanderer_notifier, :discord_character_kill_channel_id, "67890")

      # Test the function
      assert Notifications.get_discord_channel_id_for(:character_kill) == "67890"

      # Clean up
      Application.delete_env(:wanderer_notifier, :discord_character_kill_channel_id)
    end
  end
end
