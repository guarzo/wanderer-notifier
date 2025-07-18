defmodule WandererNotifierWeb.UserSocket do
  @moduledoc """
  Phoenix socket module - currently unused.

  This application is a WebSocket CLIENT that connects to external services,
  not a WebSocket SERVER that accepts incoming connections. This module
  exists for Phoenix framework compatibility but serves no functional purpose.
  """

  use Phoenix.Socket

  # No channels defined - this application does not accept WebSocket connections
  # It only makes outbound WebSocket connections to external services

  @impl true
  def connect(_params, _socket, _connect_info) do
    # Reject all connections - this application is a WebSocket client only
    :error
  end

  @impl true
  def id(_socket), do: nil
end
