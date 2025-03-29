defmodule WandererNotifier.Core.Config do
  @moduledoc """
  Core configuration module for WandererNotifier.
  Provides functions to access application configuration.
  """

  alias WandererNotifier.Config.{Features, Timings}

  @doc """
  Get the map URL.
  """
  def map_url do
    get_env(:map_url)
  end

  @doc """
  Get the map token.
  """
  def map_token do
    get_env(:map_token)
  end

  @doc """
  Get the map CSRF token.
  """
  def map_csrf_token do
    get_env(:map_csrf_token)
  end

  @doc """
  Get the map name.
  """
  def map_name do
    get_env(:map_name)
  end

  @doc """
  Get the notifier API token.
  """
  def notifier_api_token do
    get_env(:notifier_api_token)
  end

  @doc """
  Get the license key.
  """
  def license_key do
    get_env(:license_key)
  end

  @doc """
  Get the license manager API URL.
  """
  def license_manager_api_url do
    get_env(:license_manager_api_url)
  end

  @doc """
  Get the license manager API key.
  """
  def license_manager_api_key do
    get_env(:license_manager_api_key)
  end

  @doc """
  Get the Discord channel ID for a feature.
  """
  def discord_channel_id_for(feature) do
    get_env(:"discord_channel_#{feature}")
  end

  @doc """
  Get the Discord channel ID for activity charts.
  """
  def discord_channel_id_for_activity_charts do
    discord_channel_id_for(:activity_charts)
  end

  @doc """
  Check if kill charts are enabled.
  """
  def kill_charts_enabled? do
    Features.kill_charts_enabled?()
  end

  @doc """
  Check if map charts are enabled.
  """
  def map_charts_enabled? do
    Features.map_charts_enabled?()
  end

  @doc """
  Check if character tracking is enabled.
  """
  def character_tracking_enabled? do
    Features.character_tracking_enabled?()
  end

  @doc """
  Check if character notifications are enabled.
  """
  def character_notifications_enabled? do
    Features.character_notifications_enabled?()
  end

  @doc """
  Check if system notifications are enabled.
  """
  def system_notifications_enabled? do
    Features.system_notifications_enabled?()
  end

  @doc """
  Check if K-space systems should be tracked.
  """
  def track_kspace_systems? do
    Features.track_kspace_systems?()
  end

  defmodule Timings do
    @moduledoc """
    Timing-related configuration.
    """

    def characters_cache_ttl, do: WandererNotifier.Config.Timings.characters_cache_ttl()
    def systems_cache_ttl, do: WandererNotifier.Config.Timings.systems_cache_ttl()
    def reconnect_delay, do: WandererNotifier.Config.Timings.reconnect_delay()
    def maintenance_interval, do: WandererNotifier.Config.Timings.maintenance_interval()
    def static_info_cache_ttl, do: WandererNotifier.Config.Timings.static_info_cache_ttl()
  end

  @doc """
  Gets the configured value for a given key from the application environment.
  """
  def get_env(key, default \\ nil) do
    Application.get_env(:wanderer_notifier, key, default)
  end
end
