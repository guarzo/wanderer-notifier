defmodule WandererNotifierWeb.UserSocket do
  @moduledoc """
  Phoenix socket for real-time communication.

  Handles WebSocket connections for killmail streaming and other
  real-time features without requiring authentication for now.
  """

  use Phoenix.Socket

  # Define channels that can be joined
  channel("killmail:*", WandererNotifierWeb.KillmailChannel)
  channel("map:*", WandererNotifierWeb.MapChannel)

  # Socket params are passed from the client and can
  # be used to verify and authenticate a user. After
  # verification, you can put default assigns into
  # the socket that will be set for all channels, ie
  #
  #     {:ok, assign(socket, :user_id, verified_user_id)}
  #
  # To deny connection, return `:error` or `{:error, term}`.
  # To control the response the client receives in that case,
  # set `error_handler` in the websocket configuration in
  # your endpoint configuration.
  @impl true
  def connect(_params, socket, _connect_info) do
    # For now, allow all connections without authentication
    # In the future, this can be enhanced with proper auth
    {:ok, socket}
  end

  # Socket ID is used for identifying this particular connection
  # in logs and for disconnecting this particular connection.
  # Since we're not using authentication yet, we'll use a random ID.
  @impl true
  def id(_socket), do: "user_socket:#{System.unique_integer([:positive])}"
end
