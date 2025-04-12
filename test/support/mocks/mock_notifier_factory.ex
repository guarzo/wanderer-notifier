defmodule WandererNotifier.MockNotifierFactory do
  @moduledoc """
  Mock implementation of NotifierFactory for testing.
  """
  @behaviour WandererNotifier.Notifiers.FactoryBehaviour

  @impl WandererNotifier.Notifiers.FactoryBehaviour
  def create(_opts) do
    {:ok, %{notify: &notify/2}}
  end

  @impl true
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

  def notify(:send_discord_file, [url, filename, embed]) do
    {:ok, %{status_code: 200}}
  end

  def notify(:send_discord_embed_to_channel, [channel_id, embed]) do
    case {channel_id, embed} do
      {nil, _} ->
        # Handle nil channel gracefully in tests
        {:ok, %{embed: embed, channel: "default_test_channel"}}

      {_, nil} ->
        # Simplified error handling
        {:error, "Invalid embed"}

      {_, %{title: nil}} ->
        {:error, "Missing title"}

      _ ->
        {:ok, %{embed: embed, channel: channel_id}}
    end
  end

  def notify(:send_message, [message]) when is_binary(message) do
    {:ok, %{message: message}}
  end

  def notify(type, _args) do
    {:ok, %{status_code: 200}}
  end
end
