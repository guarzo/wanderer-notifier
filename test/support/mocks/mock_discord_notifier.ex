defmodule WandererNotifier.MockDiscordNotifier do
  @moduledoc """
  Mock implementation of the Discord notifier for testing.
  """

  def send_discord_embed(_embed) do
    {:ok, %{status_code: 200}}
  end

  def send_notification(_type, _data) do
    {:ok, %{status_code: 200}}
  end
end
