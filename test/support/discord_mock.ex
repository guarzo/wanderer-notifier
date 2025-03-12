defmodule WandererNotifier.Discord.NotifierMock do
  @moduledoc """
  Mock implementation of Discord notifier for testing
  """
  require Logger

  @behaviour WandererNotifier.Discord.Notifier

  @impl true
  def send_message(message) do
    Logger.info("DISCORD MOCK: #{message}")
    :ok
  end

  @impl true
  def send_embed(title, description, fields, color) do
    Logger.info("DISCORD MOCK EMBED: #{title} - #{description}")
    :ok
  end
end
