defmodule WandererNotifier.Config.Websocket do
  @moduledoc """
  Configuration module for websocket settings.

  This module centralizes all websocket-related configuration access,
  providing a standardized interface for retrieving websocket settings.
  The ZKillboard websocket URL is fixed and not configurable.
  """

  # Fixed ZKillboard websocket URL - not configurable via environment
  @zkill_websocket_url "wss://zkillboard.com/websocket/"

  @doc """
  Returns the complete websocket configuration map.
  """
  @spec config() :: map()
  def config do
    %{
      enabled: enabled(),
      url: url(),
      reconnect_delay: reconnect_delay(),
      max_reconnects: max_reconnects(),
      reconnect_window: reconnect_window()
    }
  end

  @doc """
  Returns whether the websocket functionality is enabled.
  """
  @spec enabled() :: boolean()
  def enabled do
    get_env(:enabled, true)
  end

  @doc """
  Returns the fixed ZKillboard websocket URL.
  This is not configurable via environment variables.
  """
  @spec url() :: String.t()
  def url do
    @zkill_websocket_url
  end

  @doc """
  Returns the delay between reconnection attempts in milliseconds.
  """
  @spec reconnect_delay() :: integer()
  def reconnect_delay do
    get_env(:reconnect_delay, 5000)
  end

  @doc """
  Returns the maximum number of reconnection attempts.
  """
  @spec max_reconnects() :: integer()
  def max_reconnects do
    get_env(:max_reconnects, 20)
  end

  @doc """
  Returns the time window for reconnection attempts in seconds.
  """
  @spec reconnect_window() :: integer()
  def reconnect_window do
    get_env(:reconnect_window, 3600)
  end

  @doc """
  Validates that all websocket configuration values are valid.

  Returns :ok if the configuration is valid, or {:error, reason} if not.
  """
  @spec validate() :: :ok | {:error, String.t()}
  def validate do
    # Validate reconnect_delay is a positive integer
    reconnect_delay = reconnect_delay()
    max_reconnects = max_reconnects()
    reconnect_window = reconnect_window()

    cond do
      !is_integer(reconnect_delay) || reconnect_delay <= 0 ->
        {:error, "Websocket reconnect delay must be a positive integer"}

      !is_integer(max_reconnects) || max_reconnects <= 0 ->
        {:error, "Websocket max reconnects must be a positive integer"}

      !is_integer(reconnect_window) || reconnect_window <= 0 ->
        {:error, "Websocket reconnect window must be a positive integer"}

      true ->
        :ok
    end
  end

  # Private helper function to get configuration values
  defp get_env(key, default) do
    config = Application.get_env(:wanderer_notifier, :websocket, %{})

    case config do
      config when is_map(config) ->
        Map.get(config, key, default)

      config when is_list(config) ->
        Keyword.get(config, key, default)

      _ ->
        default
    end
  end
end
