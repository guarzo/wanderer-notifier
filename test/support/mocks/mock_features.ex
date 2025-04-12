defmodule WandererNotifier.Config.MockFeatures do
  # Mock implementation that will be mocked in tests

  def get_feature_status, do: %{}

  def get_feature(key, default), do: default

  def get_env(:features, _default), do: %{}
  def get_env(key, default), do: default

  def cache_enabled?, do: true
  def notifications_enabled?, do: true
  def system_tracking_enabled?, do: true
  def system_notifications_enabled?, do: true
  def tracked_systems_notifications_enabled?, do: true
  def character_tracking_enabled?, do: true
  def character_notifications_enabled?, do: true
  def tracked_characters_notifications_enabled?, do: true
  def kill_notifications_enabled?, do: true
  def kill_charts_enabled?, do: false
  def activity_charts_enabled?, do: false
  def map_charts_enabled?, do: false
  def status_messages_disabled?, do: false
  def persistence_enabled?, do: true
end
