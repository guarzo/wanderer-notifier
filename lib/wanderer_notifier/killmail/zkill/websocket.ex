defmodule WandererNotifier.Killmail.ZKill.Websocket do
  @moduledoc """
  WebSocket client for zKillboard streaming API.

  ## Deprecation Notice
  This module is deprecated and will be removed in a future version.
  Please use `WandererNotifier.ZKill.Websocket` instead.
  """

  alias WandererNotifier.ZKill.Websocket, as: NewWebsocket
  alias WandererNotifier.Logger.Logger, as: AppLogger

  @doc """
  Starts the WebSocket connection.

  ## Deprecation Notice
  This function is deprecated and will be removed in a future version.
  Please use `WandererNotifier.ZKill.Websocket.start_link/1` instead.

  ## Parameters
    - parent: The parent process to receive messages

  ## Returns
    - {:ok, pid} if successful
    - {:error, reason} if connection fails
  """
  def start_link(parent) do
    AppLogger.websocket_debug("[DEPRECATED] Starting ZKill websocket via legacy module")
    NewWebsocket.start_link(parent)
  end

  @doc """
  Subscribes to the zkillboard feed.

  ## Deprecation Notice
  This function is deprecated and will be removed in a future version.
  Please use `WandererNotifier.ZKill.Websocket.subscribe/1` instead.
  """
  def subscribe(client) do
    AppLogger.websocket_debug("[DEPRECATED] Subscribing to ZKill feed via legacy module")
    NewWebsocket.subscribe(client)
  end
end
