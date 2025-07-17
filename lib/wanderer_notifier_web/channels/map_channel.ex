defmodule WandererNotifierWeb.MapChannel do
  @moduledoc """
  Phoenix channel for real-time map updates.

  This channel allows clients to subscribe to map-related events
  such as system changes, character movements, and wormhole connections.
  """
  use Phoenix.Channel

  @doc """
  Joins the map channel.

  Currently allows all connections. In the future, this could be
  enhanced with authorization based on the topic.
  """
  def join("map:" <> _topic, _params, socket) do
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
