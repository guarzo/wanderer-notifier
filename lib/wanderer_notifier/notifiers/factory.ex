defmodule WandererNotifier.Notifiers.Factory do
  @moduledoc """
  Factory module for creating and managing notifiers.
  """

  require Logger
  alias WandererNotifier.Config.Features
  alias WandererNotifier.Config.Notifications
  alias WandererNotifier.Notifiers.Discord.Notifier, as: DiscordNotifier
  alias WandererNotifier.Notifiers.TestNotifier

  @doc """
  Sends a notification using the appropriate notifier based on the current configuration.
  """
  def notify(type, data) do
    if Features.notifications_enabled?() do
      do_notify(get_notifier(), type, data)
    else
      {:error, :notifications_disabled}
    end
  end

  @doc """
  Gets the appropriate notifier based on the current configuration.
  """
  def get_notifier do
    if Features.test_mode_enabled?() do
      TestNotifier
    else
      DiscordNotifier
    end
  end

  defp do_notify(notifier, :send_system_kill_discord_embed, [embed]) do
    # Get the channel ID for system kill notifications
    channel_id = Notifications.channel_id(:system_kill)

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
    channel_id = Notifications.channel_id(:character_kill)

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
end
