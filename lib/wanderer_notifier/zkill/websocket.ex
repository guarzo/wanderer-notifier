defmodule WandererNotifier.ZKill.Websocket do
  @moduledoc """
  WebSocket client for zKillboard streaming API.
  """

  use WebSockex
  alias WandererNotifier.Logger.Logger, as: AppLogger
  alias WandererNotifier.Config.Websocket, as: WSConfig

  @zkill_ws_url "wss://zkillboard.com/websocket/"

  @doc """
  Starts the WebSocket connection.

  ## Parameters
    - parent: The parent process to receive messages

  ## Returns
    - {:ok, pid} if successful
    - {:error, reason} if connection fails
  """
  def start_link(parent) do
    AppLogger.websocket_debug("Starting ZKill websocket with parent", parent: inspect(parent))

    state = %{
      parent: parent,
      subscribed: false
    }

    case WebSockex.start_link(@zkill_ws_url, __MODULE__, state, name: __MODULE__) do
      {:ok, pid} ->
        AppLogger.websocket_info("ZKill websocket started", pid: inspect(pid))
        subscribe(pid)
        {:ok, pid}

      error ->
        AppLogger.websocket_error("Failed to start ZKill websocket", error: inspect(error))
        error
    end
  end

  @doc """
  Subscribes to the zkillboard feed.
  """
  def subscribe(client) do
    channels = WSConfig.subscribe_channels()

    Enum.each(channels, fn channel ->
      subscription = Jason.encode!(%{action: "sub", channel: channel})
      WebSockex.send_frame(client, {:text, subscription})
      AppLogger.websocket_info("Subscribed to channel", channel: channel)
    end)
  end

  # WebSockex Callbacks

  @impl WebSockex
  def handle_connect(_conn, state) do
    AppLogger.websocket_info("ZKill websocket connected")
    {:ok, state}
  end

  @impl WebSockex
  def handle_frame({:text, msg}, state) do
    try do
      decoded = Jason.decode!(msg)

      # Forward the message to the parent process
      if state.parent do
        send(state.parent, {:zkill_message, decoded})
      end

      {:ok, state}
    rescue
      e ->
        AppLogger.websocket_error("ZKill message decode error",
          error: Exception.message(e),
          message: msg
        )

        {:ok, state}
    end
  end

  @impl WebSockex
  def handle_disconnect(%{reason: reason}, state) do
    AppLogger.websocket_warn("ZKill websocket disconnected", reason: inspect(reason))

    # Notify parent about disconnection
    if state.parent do
      send(state.parent, :ws_disconnected)
    end

    # Don't attempt to reconnect here, let the parent handle that
    {:ok, state}
  end

  @impl WebSockex
  def terminate(reason, state) do
    AppLogger.websocket_warn("ZKill websocket terminated", reason: inspect(reason))

    # Notify parent about disconnection
    if state.parent do
      send(state.parent, :ws_disconnected)
    end

    # Normal WebSockex termination
    exit(:normal)
  end
end
