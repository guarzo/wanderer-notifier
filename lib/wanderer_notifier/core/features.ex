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
  Checks if activity charts are enabled.
  """
  def activity_charts_enabled? do
    get_config(:activity_charts_enabled, false)
  end

  @doc """
  Checks if kill charts are enabled.
  """
  def kill_charts_enabled? do
    get_config(:kill_charts_enabled, false)
  end

  @doc """
  Checks if map charts are enabled.
  """
  def map_charts_enabled? do
    get_config(:map_charts_enabled, false)
  end

  @doc """
  Checks if character notifications are enabled.
  """
  def character_notifications_enabled? do
    Application.get_env(:wanderer_notifier, :features, %{})
    |> Map.get(:character_notifications_enabled, true)
  end

  @doc """
  Checks if system notifications are enabled.
  """
  def system_notifications_enabled? do
    Application.get_env(:wanderer_notifier, :features, %{})
    |> Map.get(:system_notifications_enabled, true)
  end

  @doc """
  Checks if character tracking is enabled.
  """
  def character_tracking_enabled? do
    get_config(:character_tracking_enabled, false)
  end

  @doc """
  Checks if system tracking is enabled.
  """
  def system_tracking_enabled? do
    get_config(:system_tracking_enabled, false)
  end

  @doc """
  Checks if k-space system tracking is enabled.
  """
  def track_kspace_systems? do
    get_config(:track_kspace_systems, false)
  end

  @doc """
  Checks if tracked systems notifications are enabled.
  """
  def tracked_systems_notifications_enabled? do
    get_config(:tracked_systems_notifications_enabled, false)
  end

  @doc """
  Checks if tracked characters notifications are enabled.
  """
  def tracked_characters_notifications_enabled? do
    get_config(:tracked_characters_notifications_enabled, false)
  end

  @doc """
  Checks if kill notifications are enabled.
  """
  def kill_notifications_enabled? do
    Application.get_env(:wanderer_notifier, :features, %{})
    |> Map.get(:kill_notifications_enabled, true)
  end

  @doc """
  Check if we should load tracking data (systems and characters) for use in kill notifications.
  """
  def should_load_tracking_data? do
    kill_notifications_enabled?()
  end

  @doc """
  Gets the complete feature status map.
  """
  def get_feature_status do
    %{
      activity_charts: activity_charts_enabled?(),
      kill_charts: kill_charts_enabled?(),
      map_charts: map_charts_enabled?(),
      character_notifications: character_notifications_enabled?(),
      system_notifications: system_notifications_enabled?(),
      character_tracking: character_tracking_enabled?(),
      system_tracking: system_tracking_enabled?(),
      track_kspace_systems: track_kspace_systems?(),
      tracked_systems_notifications: tracked_systems_notifications_enabled?(),
      tracked_characters_notifications: tracked_characters_notifications_enabled?(),
      kill_notifications: kill_notifications_enabled?()
    }
  end

  @feature_checks %{
    activity_charts: &WandererNotifier.Core.Features.activity_charts_enabled?/0,
    kill_charts: &WandererNotifier.Core.Features.kill_charts_enabled?/0,
    map_charts: &WandererNotifier.Core.Features.map_charts_enabled?/0,
    character_notifications: &WandererNotifier.Core.Features.character_notifications_enabled?/0,
    system_notifications: &WandererNotifier.Core.Features.system_notifications_enabled?/0,
    character_tracking: &WandererNotifier.Core.Features.character_tracking_enabled?/0,
    system_tracking: &WandererNotifier.Core.Features.system_tracking_enabled?/0,
    track_kspace: &WandererNotifier.Core.Features.track_kspace_systems?/0,
    tracked_systems_notifications:
      &WandererNotifier.Core.Features.tracked_systems_notifications_enabled?/0,
    tracked_characters_notifications:
      &WandererNotifier.Core.Features.tracked_characters_notifications_enabled?/0,
    kill_notifications: &WandererNotifier.Core.Features.kill_notifications_enabled?/0
  }

  @doc """
  Checks if a specific feature is enabled.
  """
  def enabled?(feature) when is_atom(feature) do
    case Map.get(@feature_checks, feature) do
      nil -> false
      check_fn -> check_fn.()
    end
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
  Checks if notifications are enabled.
  """
  def notifications_enabled? do
    Application.get_env(:wanderer_notifier, :features, %{})
    |> Map.get(:notifications_enabled, true)
  end

  @doc """
  Checks if test mode is enabled.
  """
  def test_mode_enabled? do
    Application.get_env(:wanderer_notifier, :features, %{})
    |> Map.get(:test_mode_enabled, false)
  end
end
