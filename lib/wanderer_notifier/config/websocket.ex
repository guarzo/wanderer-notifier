defmodule WandererNotifier.Config.Websocket do
  @moduledoc """
  Configuration for the WebSocket clients.

  This module defines the configuration settings for WebSocket interactions,
  such as which channels to subscribe to for the ZKillboard feed.
  """

  @zkill_ws_url "wss://zkillboard.com/websocket/"

  @doc """
  Returns the ZKillboard WebSocket URL.

  This URL is fixed and not configurable.

  ## Returns
    - The ZKillboard WebSocket URL as a string
  """
  @spec url() :: String.t()
  def url, do: @zkill_ws_url

  @doc """
  Checks if WebSocket connections are enabled.

  This can be disabled via environment variable for testing or
  during development to prevent unwanted connections.

  ## Returns
    - true if WebSocket connections are enabled
    - false if disabled
  """
  @spec enabled() :: boolean()
  def enabled do
    case System.get_env("WANDERER_FEATURE_DISABLE_WEBSOCKET") do
      "true" -> false
      _ -> true
    end
  end

  @doc """
  Returns the list of channels to subscribe to for the ZKillboard WebSocket.

  Currently subscribes to the "killstream" channel which receives all kills
  from the ZKillboard websocket.

  ## Returns
    - A list of channel names as strings
  """
  @spec subscribe_channels() :: [String.t()]
  def subscribe_channels do
    ["killstream"]
  end
end
