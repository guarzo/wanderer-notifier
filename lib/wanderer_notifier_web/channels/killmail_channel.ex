defmodule WandererNotifierWeb.KillmailChannel do
  @moduledoc """
  Phoenix channel for real-time killmail updates.

  This channel allows clients to subscribe to killmail events
  and receive real-time notifications when new kills occur.
  """
  use Phoenix.Channel

  @doc """
  Joins the killmail channel.

  Currently allows all connections. In the future, this could be
  enhanced with authorization based on the topic.
  """
  def join("killmail:" <> _topic, _params, socket) do
    {:ok, socket}
  end

  @doc """
  Handles incoming messages from the client.
  """
  def handle_in("ping", _payload, socket) do
    {:reply, {:ok, %{message: "pong"}}, socket}
  end

  # Catch-all for unhandled messages
  def handle_in(_event, _payload, socket) do
    {:noreply, socket}
  end
end
