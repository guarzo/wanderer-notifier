defmodule WandererNotifier.DiscordMock do
  @moduledoc """
  Mock implementation of Discord notifier for testing
  """

  def send_message(message) do
    # Just log the message during tests instead of sending to Discord
    IO.puts("DISCORD MOCK: #{message}")
    :ok
  end

  def send_embed(_title, _description, _fields, _color) do
    # Mock implementation for embed messages
    :ok
  end
end
