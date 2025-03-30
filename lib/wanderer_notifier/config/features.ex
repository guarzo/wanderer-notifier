defmodule WandererNotifier.Config.Features do
  @moduledoc """
  Configuration module for feature flags and limits.
  """

  @doc """
  Gets all feature limits.
  """
  def get_all_limits do
    get_env(:features, %{})
  end

  @doc """
  Checks if a specific feature is enabled.
  """
  def enabled?(feature) when is_atom(feature) do
    get_env(feature, false)
  end

  @doc """
  Checks if character tracking is enabled.
  """
  def character_tracking_enabled? do
    enabled?(:character_tracking)
  end

  @doc """
  Checks if map charts are enabled.
  """
  def map_charts_enabled? do
    enabled?(:map_charts)
  end

  @doc """
  Gets the map token from configuration.
  """
  def map_token do
    get_env(:map_token)
  end

  @doc """
  Gets the map configuration.
  """
  def get_map_config do
    get_env(:map_config, %{})
  end

  @doc """
  Checks if tracking k-space systems is enabled.
  """
  def track_kspace_systems? do
    enabled?(:track_kspace_systems)
  end

  @doc """
  Gets environment variable value with optional default.
  """
  def get_env(key, default \\ nil) do
    Application.get_env(:wanderer_notifier, key, default)
  end

  @doc """
  Gets the feature configuration for a given feature.
  """
  def get_config(feature, default \\ nil) do
    get_env(:features, %{})
    |> Map.get(feature, default)
  end

  @doc """
  Check if kill notifications are enabled.
  """
  def kill_notifications_enabled? do
    get_config(:kill_notifications, false)
  end

  @doc """
  Check if character notifications are enabled.
  """
  def character_notifications_enabled? do
    get_config(:character_notifications, false)
  end

  @doc """
  Check if system notifications are enabled.
  """
  def system_notifications_enabled? do
    get_config(:system_notifications, false)
  end

  @doc """
  Get the Discord channel ID for activity charts.
  """
  def discord_channel_id_for_activity_charts do
    get_config(:activity_charts_channel_id)
  end

  @doc """
  Get the static info cache TTL.
  """
  def static_info_cache_ttl do
    get_env(:static_info_cache_ttl, 3600)
  end

  @doc """
  Get the status of all features.
  """
  def get_feature_status do
    %{
      kill_charts: kill_charts_enabled?(),
      map_charts: map_charts_enabled?(),
    }
  end

  @doc """
  Check if kill charts feature is enabled.
  """
  def kill_charts_enabled? do
    get_config(:kill_charts, true)
  end

end
