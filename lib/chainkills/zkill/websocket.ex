defmodule ChainKills.ZKill.Websocket do
  @moduledoc """
  WebSockex client connecting to zKill's killstream and forwarding messages to the parent GenServer.
  """
  use WebSockex
  require Logger

  def start_link(parent, url) do
    WebSockex.start_link(url, __MODULE__, parent)
  end

  def init(parent) do
    send(self(), :subscribe)
    {:ok, parent}
  end

  def handle_connect(_conn, parent) do
    Logger.info("Connected to zKill websocket.")
    {:ok, parent}
  end

  def handle_info(:subscribe, parent) do
    msg = Jason.encode!(%{"action" => "sub", "channel" => "killstream"})
    {:reply, {:text, msg}, parent}
  end

  def handle_frame({:text, msg}, parent) do
    send(parent, {:zkill_message, msg})
    {:ok, parent}
  end

  def handle_disconnect(_reason, parent) do
    send(parent, :ws_disconnected)
    {:ok, parent}
  end
end
