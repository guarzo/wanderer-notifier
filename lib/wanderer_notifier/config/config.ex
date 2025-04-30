defmodule WandererNotifier.Config.Config do
  @moduledoc """
  Configuration module for WandererNotifier.
  Provides functions to access application configuration.
  """

  alias WandererNotifier.Config.Features

  def map_url do
    get_env(:map_url)
  end

  def map_token do
    get_env(:map_token)
  end

  def map_csrf_token do
    get_env(:map_csrf_token)
  end

  def map_name do
    get_env(:map_name)
  end

  def notifier_api_token do
    get_env(:notifier_api_token)
  end

  def license_key do
    get_env(:license_key)
  end

  def license_manager_api_url do
    get_env(:license_manager_api_url)
  end

  def license_manager_api_key do
    get_env(:license_manager_api_key)
  end

  def discord_channel_id_for(feature) do
    get_env(:"discord_channel_#{feature}")
  end

  def character_tracking_enabled? do
    Features.character_tracking_enabled?()
  end

  def character_notifications_enabled? do
    Features.character_notifications_enabled?()
  end

  def system_notifications_enabled? do
    Features.system_notifications_enabled?()
  end

  def track_kspace_systems? do
    Features.track_kspace_systems?()
  end

  def get_map_config do
    get_env(:map_config, %{})
  end

  def static_info_cache_ttl do
    get_env(:static_info_cache_ttl, 3600)
  end

  def get_feature_status do
    %{
      system_tracking_enabled: system_notifications_enabled?(),
      character_tracking_enabled: character_tracking_enabled?()
    }
  end

  def get_env(key, default \\ nil) do
    Application.get_env(:wanderer_notifier, key, default)
  end

  @doc """
  Get the map API key from configuration
  """
  def map_api_key do
    Application.get_env(:wanderer_notifier, :map_api_key, "")
  end

  def discord_webhook_url do
    get_env(:discord_webhook_url)
  end
end
