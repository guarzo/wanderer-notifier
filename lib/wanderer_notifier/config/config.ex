defmodule WandererNotifier.Config.Config do
  @moduledoc """
  Configuration module for WandererNotifier.
  Provides functions to access application configuration.
  """
  @behaviour WandererNotifier.Config.Behaviour

  alias WandererNotifier.Config.Features

  @impl true
  def map_url do
    get_env(:map_url)
  end

  @impl true
  def map_token do
    get_env(:map_token)
  end

  @impl true
  def map_csrf_token do
    get_env(:map_csrf_token)
  end

  @impl true
  def map_name do
    get_env(:map_name)
  end

  @impl true
  def notifier_api_token do
    get_env(:notifier_api_token)
  end

  @impl true
  def license_key do
    get_env(:license_key)
  end

  @impl true
  def license_manager_api_url do
    get_env(:license_manager_api_url)
  end

  @impl true
  def license_manager_api_key do
    get_env(:license_manager_api_key)
  end

  @impl true
  def discord_channel_id_for(feature) do
    get_env(:"discord_channel_#{feature}")
  end

  @impl true
  def discord_channel_id_for_activity_charts do
    discord_channel_id_for(:activity_charts)
  end

  @impl true
  def kill_charts_enabled? do
    Features.kill_charts_enabled?()
  end

  @impl true
  def map_charts_enabled? do
    Features.map_charts_enabled?()
  end

  @impl true
  def character_tracking_enabled? do
    Features.character_tracking_enabled?()
  end

  @impl true
  def character_notifications_enabled? do
    Features.character_notifications_enabled?()
  end

  @impl true
  def system_notifications_enabled? do
    Features.system_notifications_enabled?()
  end

  @impl true
  def track_kspace_systems? do
    Features.track_kspace_systems?()
  end

  @impl true
  def get_map_config do
    get_env(:map_config, %{})
  end

  @impl true
  def static_info_cache_ttl do
    get_env(:static_info_cache_ttl, 3600)
  end

  @impl true
  def get_feature_status do
    %{
      kill_notifications_enabled: kill_charts_enabled?(),
      system_tracking_enabled: system_notifications_enabled?(),
      character_tracking_enabled: character_tracking_enabled?(),
      activity_charts: map_charts_enabled?()
    }
  end

  @impl true
  def get_env(key, default \\ nil) do
    Application.get_env(:wanderer_notifier, key, default)
  end
end
