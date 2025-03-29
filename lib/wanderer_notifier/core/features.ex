defmodule WandererNotifier.Core.Features do
  @moduledoc """
  Module for checking feature flags and configuration.
  """

  @doc """
  Gets a configuration value from the application environment.
  """
  def get_config(key, default \\ nil) do
    Application.get_env(:wanderer_notifier, key, default)
  end

  @doc """
  Gets a feature flag from the features map.
  """
  def get_feature(key, default \\ false) do
    Application.get_env(:wanderer_notifier, :features, %{})
    |> Map.get(key, default)
  end

  @doc """
  Checks if a specific feature is enabled.
  """
  def enabled?(feature) when is_atom(feature) do
    get_feature(feature, false)
  end

  @doc """
  Checks if activity charts are enabled.
  """
  def activity_charts_enabled? do
    get_feature(:activity_charts, false)
  end

  @doc """
  Checks if kill charts are enabled.
  """
  def kill_charts_enabled? do
    get_feature(:kill_charts, false)
  end

  @doc """
  Checks if map charts are enabled.
  """
  def map_charts_enabled? do
    get_feature(:map_charts, false)
  end

  @doc """
  Checks if character notifications are enabled.
  """
  def character_notifications_enabled? do
    get_feature(:character_notifications_enabled, true)
  end

  @doc """
  Checks if system notifications are enabled.
  """
  def system_notifications_enabled? do
    get_feature(:system_notifications_enabled, true)
  end

  @doc """
  Checks if character tracking is enabled.
  """
  def character_tracking_enabled? do
    get_feature(:character_tracking_enabled, false)
  end

  @doc """
  Checks if system tracking is enabled.
  """
  def system_tracking_enabled? do
    get_feature(:system_tracking_enabled, false)
  end

  @doc """
  Checks if k-space system tracking is enabled.
  """
  def track_kspace_systems? do
    get_feature(:track_kspace_systems, false)
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
  Checks if kill notifications are enabled.
  """
  def kill_notifications_enabled? do
    get_feature(:kill_notifications_enabled, true)
  end

  @doc """
  Check if we should load tracking data (systems and characters) for use in kill notifications.
  """
  def should_load_tracking_data? do
    kill_notifications_enabled?()
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
  Checks if a limit has been reached for a specific resource.
  """
  def limit_reached?(resource, current_count) do
    limit = get_limit(resource)
    not is_nil(limit) and current_count >= limit
  end

  @doc """
  Gets the limit for a specific resource.
  """
  def get_limit(resource) do
    get_config(resource, nil)
  end

  @doc """
  Gets all limits.
  """
  def get_all_limits do
    %{
      tracked_systems: get_limit(:tracked_systems),
      tracked_characters: get_limit(:tracked_characters),
      notification_history: get_limit(:notification_history)
    }
  end

  @doc """
  Gets the complete feature status map.
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
end
