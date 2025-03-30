defmodule WandererNotifier.Config.Features do
  @moduledoc """
  Configuration module for feature flags and limits.
  """

  @doc """
  Gets all feature limits.
  """
  def get_all_limits do
    %{
      tracked_systems: get_limit(:tracked_systems),
      tracked_characters: get_limit(:tracked_characters),
      notification_history: get_limit(:notification_history)
    }
  end

  @doc """
  Gets a limit for a specific resource.
  """
  def get_limit(resource) do
    get_env(resource, nil)
  end

  @doc """
  Gets a feature flag from the features map.
  """
  def get_feature(key, default \\ false) do
    features_map = Application.get_env(:wanderer_notifier, :features, %{})

    # Try both atom and string keys
    atom_key = if is_atom(key), do: key, else: String.to_atom("#{key}")
    string_key = if is_binary(key), do: key, else: Atom.to_string(key)

    # Check if each key exists
    atom_exists = Map.has_key?(features_map, atom_key)
    string_exists = Map.has_key?(features_map, string_key)

    # Get the value based on which key exists
    cond do
      atom_exists -> Map.get(features_map, atom_key)
      string_exists -> Map.get(features_map, string_key)
      true -> default
    end
  end

  @doc """
  Checks if a specific feature is enabled.
  """
  def enabled?(feature) when is_atom(feature) do
    get_feature(feature, true)
  end

  @doc """
  Checks if character tracking is enabled.
  """
  def character_tracking_enabled? do
    get_feature(:character_tracking_enabled, false)
  end

  @doc """
  Checks if map charts are enabled.
  """
  def map_charts_enabled? do
    get_feature(:map_charts, false)
  end

  @doc """
  Checks if activity charts are enabled.
  """
  def activity_charts_enabled? do
    get_feature(:activity_charts, false)
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
    # Get feature flag and log it
    get_feature(:track_kspace_systems, true)
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
  def get_config(key, default \\ nil) do
    Application.get_env(:wanderer_notifier, key, default)
  end

  @doc """
  Check if kill notifications are enabled.
  """
  def kill_notifications_enabled? do
    # Get feature flag and log it
    get_feature(:kill_notifications_enabled, true)
  end

  @doc """
  Check if character notifications are enabled.
  """
  def character_notifications_enabled? do
    get_feature(:character_notifications_enabled, true)
  end

  @doc """
  Check if system notifications are enabled.
  """
  def system_notifications_enabled? do
    get_feature(:system_notifications_enabled, true)
  end

  @doc """
  Checks if tracked systems notifications are enabled.
  """
  def tracked_systems_notifications_enabled? do
    get_feature(:tracked_systems_notifications_enabled, false)
  end

  @doc """
  Checks if tracked characters notifications are enabled.
  """
  def tracked_characters_notifications_enabled? do
    get_feature(:tracked_characters_notifications_enabled, false)
  end

  @doc """
  Checks if notifications are enabled.
  """
  def notifications_enabled? do
    get_feature(:notifications_enabled, true)
  end

  @doc """
  Checks if test mode is enabled.
  """
  def test_mode_enabled? do
    get_feature(:test_mode_enabled, false)
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
  Check if we should load tracking data (systems and characters) for use in kill notifications.
  """
  def should_load_tracking_data? do
    kill_notifications_enabled?()
  end

  @doc """
  Checks if system tracking is enabled.
  """
  def system_tracking_enabled? do
    get_feature(:system_tracking_enabled, true)
  end

  @doc """
  Get the status of all features.
  """
  def get_feature_status do
    %{
      activity_charts: activity_charts_enabled?(),
      kill_charts: kill_charts_enabled?(),
      map_charts: map_charts_enabled?(),
      character_notifications_enabled: character_notifications_enabled?(),
      system_notifications_enabled: system_notifications_enabled?(),
      character_tracking_enabled: character_tracking_enabled?(),
      system_tracking_enabled: system_tracking_enabled?(),
      tracked_systems_notifications_enabled: tracked_systems_notifications_enabled?(),
      tracked_characters_notifications_enabled: tracked_characters_notifications_enabled?(),
      kill_notifications_enabled: kill_notifications_enabled?(),
      notifications_enabled: notifications_enabled?()
    }
  end

  @doc """
  Check if kill charts feature is enabled.
  """
  def kill_charts_enabled? do
    get_feature(:kill_charts, false)
  end
end
