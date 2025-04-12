defmodule WandererNotifier.Support.MockFeatures do
  @moduledoc """
  Support implementation for MockFeatures to use with stub_with.
  Implements all the required callbacks.
  """

  # Standard callbacks
  def get_feature_status do
    %{
      activity_charts: true,
      kill_charts: true,
      map_charts: true,
      character_notifications_enabled: true,
      system_notifications_enabled: true,
      character_tracking_enabled: true,
      system_tracking_enabled: true,
      tracked_systems_notifications_enabled: true,
      tracked_characters_notifications_enabled: true,
      kill_notifications_enabled: true,
      notifications_enabled: true
    }
  end

  def get_feature(:status_messages_disabled, _default), do: false
  def get_feature(_key, default), do: default

  def get_env(:features, _default), do: %{status_messages_disabled: false}
  def get_env(_key, default), do: default

  # Feature status checks
  def cache_enabled?, do: true
  def notifications_enabled?, do: true
  def system_tracking_enabled?, do: true
  def system_notifications_enabled?, do: true
  def tracked_systems_notifications_enabled?, do: true
  def character_tracking_enabled?, do: true
  def character_notifications_enabled?, do: true
  def tracked_characters_notifications_enabled?, do: true
  def kill_notifications_enabled?, do: true
  def kill_charts_enabled?, do: true
  def activity_charts_enabled?, do: true
  def map_charts_enabled?, do: true
  def status_messages_disabled?, do: false
  def persistence_enabled?, do: true
end

defmodule WandererNotifier.Config.MockFeatures do
  # Mock implementation that will be mocked in tests

  def get_feature_status, do: %{}

  def get_feature(key, default), do: default

  def get_env(:features, _default), do: %{}
  def get_env(key, default), do: default

  def cache_enabled?, do: false
  def notifications_enabled?, do: false
  def system_tracking_enabled?, do: false
  def system_notifications_enabled?, do: false
  def tracked_systems_notifications_enabled?, do: false
  def character_tracking_enabled?, do: false
  def character_notifications_enabled?, do: false
  def tracked_characters_notifications_enabled?, do: false
  def kill_notifications_enabled?, do: false
  def kill_charts_enabled?, do: false
  def activity_charts_enabled?, do: false
  def map_charts_enabled?, do: false
  def status_messages_disabled?, do: false
  def persistence_enabled?, do: true
end
