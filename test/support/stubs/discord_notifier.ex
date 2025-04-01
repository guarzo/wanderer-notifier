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
end
