defmodule WandererNotifier.Test.Stubs.DiscordNotifier do
  @moduledoc """
  Stub implementation of the Discord notifier for testing.
  """

  @behaviour WandererNotifier.Notifiers.DiscordNotifierBehaviour

  @impl true
  def send_notification(_type, _data) do
    {:ok, :sent}
  end

  @impl true
  def send_to_channel(_channel_id, _data) do
    {:ok, :sent}
  end

  @impl true
  def send_discord_embed(_embed) do
    {:ok, :sent}
  end

  @doc """
  Additional implementation for sending Discord embeds to channels.
  This function is called via the NotifierFactory for startup notifications.
  """
  def send_notification(:send_discord_embed_to_channel, [_channel_id, _embed]) do
    # Simulates successful message sending without actually calling Discord API
    {:ok, :sent}
  end
end
