defmodule WandererNotifier.Notifications.Dispatcher do
  @moduledoc """
  Dispatcher for creating and sending notifications.
  Provides a unified interface for sending notifications of various types.
  """

  require Logger
  alias WandererNotifier.Config
  alias WandererNotifier.Notifiers.Discord.Notifier, as: DiscordNotifier
  alias WandererNotifier.Notifiers.TestNotifier

  @doc """
  Sends a notification using the appropriate notifier based on the current configuration.

  ## Parameters
  - type: The type of notification to send (e.g. :send_discord_embed)
  - data: The data to include in the notification (content varies based on type)

  ## Returns
  - {:ok, result} on success
  - {:error, reason} on failure
  """
  def run(type, data) do
    if Config.notifications_enabled?() do
      do_notify(get_notifier(), type, data)
    else
      {:error, :notifications_disabled}
    end
  end

  @doc """
  Gets the appropriate notifier based on the current configuration.
  """
  def get_notifier do
    if Config.test_mode_enabled?(), do: TestNotifier, else: DiscordNotifier
  end

  defp do_notify(notifier, :send_system_kill_discord_embed, [embed]) do
    # Get the channel ID for system kill notifications
    channel_id = Config.discord_system_kill_channel_id()

    if is_nil(channel_id) do
      # Fall back to main channel if no dedicated channel is configured
      notifier.send_notification(:send_discord_embed, [embed])
    else
      # Send to the system kill channel
      notifier.send_notification(:send_discord_embed_to_channel, [channel_id, embed])
    end
  end

  defp do_notify(notifier, :send_character_kill_discord_embed, [embed]) do
    # Get the channel ID for character kill notifications
    channel_id = Config.discord_character_kill_channel_id()

    if is_nil(channel_id) do
      # Fall back to main channel if no dedicated channel is configured
      notifier.send_notification(:send_discord_embed, [embed])
    else
      # Send to the character kill channel
      notifier.send_notification(:send_discord_embed_to_channel, [channel_id, embed])
    end
  end

  defp do_notify(notifier, type, data) do
    notifier.send_notification(type, data)
  end

  @doc """
  Sends a system activity notification.

  ## Parameters
  - embed: The formatted embed to send

  ## Returns
  - {:ok, result} on success
  - {:error, reason} on failure
  """
  def send_system_activity_notification(embed) do
    run(:send_system_activity_discord_embed, [embed])
  end

  @doc """
  Sends a character activity notification.

  ## Parameters
  - embed: The formatted embed to send

  ## Returns
  - {:ok, result} on success
  - {:error, reason} on failure
  """
  def send_character_activity_notification(embed) do
    run(:send_character_activity_discord_embed, [embed])
  end

  @doc """
  Sends a plain text message notification.

  ## Parameters
  - message: The text message to send

  ## Returns
  - {:ok, result} on success
  - {:error, reason} on failure
  """
  def send_message(message) do
    run(:send_message, [message])
  end

  @doc """
  Sends a system notification.

  ## Parameters
  - embed: The formatted embed to send

  ## Returns
  - {:ok, result} on success
  - {:error, reason} on failure
  """
  def send_system_notification(embed) do
    run(:send_system_discord_embed, [embed])
  end
end
