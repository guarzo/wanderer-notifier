defmodule WandererNotifier.Test.Stubs.DiscordNotifier do
  @moduledoc """
  Stub implementation of the Discord notifier for testing.
  """

  def send_notification(_type, _data) do
    {:ok, :sent}
  end

  def send_to_channel(_channel_id, _data) do
    {:ok, :sent}
  end

  def send_discord_embed(_embed) do
    {:ok, :sent}
  end
end
