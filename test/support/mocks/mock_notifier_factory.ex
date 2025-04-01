defmodule WandererNotifier.MockNotifierFactory do
  @moduledoc """
  Mock implementation of NotifierFactory for testing.
  """
  @behaviour WandererNotifier.Notifiers.FactoryBehaviour

  @impl true
  def notify(:send_discord_embed, [embed]) do
    {:ok, %{embed: embed}}
  end
end
