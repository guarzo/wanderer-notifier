defmodule WandererNotifier.MockNotifierFactory do
  @moduledoc """
  Mock implementation of NotifierFactory for testing.
  """

  def notify(:send_discord_embed, [embed]) do
    case embed do
      nil ->
        # Simplified error handling
        {:error, "Invalid embed"}

      %{title: nil} ->
        {:error, "Missing title"}

      _ ->
        {:ok, %{embed: embed}}
    end
  end

  def notify(type, _args) do
    {:error, "Unsupported notification type: #{inspect(type)}"}
  end
end
