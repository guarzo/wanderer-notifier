defmodule WandererNotifier.Config do
  @moduledoc """
  Configuration module for WandererNotifier.
  """

  @doc """
  Checks if map charts are enabled.
  """
  def map_charts_enabled? do
    Application.get_env(:wanderer_notifier, :map_charts_enabled, false)
  end

  @doc """
  Gets the Discord channel ID for activity charts.
  """
  def discord_channel_id_for_activity_charts do
    Application.get_env(:wanderer_notifier, :discord_channel_id_activity_charts)
  end

  @doc """
  Gets the map token from configuration.
  """
  def map_token do
    Application.get_env(:wanderer_notifier, :map_token)
  end

  @doc """
  Gets the map configuration.
  """
  def get_map_config do
    Application.get_env(:wanderer_notifier, :map_config, %{})
  end

  @doc """
  Gets the static info cache TTL.
  """
  def static_info_cache_ttl do
    Application.get_env(:wanderer_notifier, :static_info_cache_ttl, 3600)
  end
end
