defmodule WandererNotifier.Core.Application.API do
  @moduledoc """
  Public API for accessing application configuration and status.

  This module provides a clean interface for accessing various application settings
  and configuration values. All functions delegate to the appropriate modules.
  """

  alias WandererNotifier.Config
  alias WandererNotifier.Core.Stats

  # --- Environment and Version ---

  @doc """
  Gets the current environment.
  """
  def env, do: Application.get_env(:wanderer_notifier, :env)

  @doc """
  Gets the current version.
  """
  def version, do: Application.spec(:wanderer_notifier)[:vsn]

  # --- License Configuration ---

  @doc """
  Gets the current license status.
  """
  def license_status, do: :ok

  @doc """
  Gets the current license key.
  """
  def license_key, do: Config.license_key()

  @doc """
  Gets the current license manager API URL.
  """
  def license_manager_api_url, do: Config.license_manager_api_url()

  @doc """
  Gets the current license manager API key.
  """
  def license_manager_api_key, do: Config.license_manager_api_key()

  # --- Map Configuration ---

  @doc """
  Gets the current map URL.
  """
  def map_url, do: Config.map_url()

  @doc """
  Gets the current map token.
  """
  def map_token, do: Config.map_token()

  @doc """
  Gets the current map name.
  """
  def map_name, do: Config.map_name()

  @doc """
  Gets the current map API URL.
  """
  @deprecated "Use map_url/0 instead"
  def map_api_url, do: Config.map_url()

  @doc """
  Gets the current map URL with name.
  """
  def map_url_with_name, do: Config.map_url_with_name()

  @doc """
  Gets the current map API key.
  """
  def map_api_key, do: Config.map_api_key()

  # --- Discord Configuration ---

  @doc """
  Gets the current Discord channel ID.
  """
  def discord_channel_id, do: Config.discord_channel_id()

  @doc """
  Gets the current Discord system kill channel ID.
  """
  def discord_system_kill_channel_id, do: Config.discord_system_kill_channel_id()

  @doc """
  Gets the current Discord character kill channel ID.
  """
  def discord_character_kill_channel_id, do: Config.discord_character_kill_channel_id()

  @doc """
  Gets the current Discord system channel ID.
  """
  def discord_system_channel_id, do: Config.discord_system_channel_id()

  @doc """
  Gets the current Discord character channel ID.
  """
  def discord_character_channel_id, do: Config.discord_character_channel_id()

  @doc """
  Gets the current Discord charts channel ID.
  """
  def discord_charts_channel_id, do: Config.discord_charts_channel_id()

  @doc """
  Gets the current Discord bot token.
  """
  def discord_bot_token, do: Config.discord_bot_token()

  @doc """
  Gets the current Discord webhook URL.
  """
  def discord_webhook_url, do: Config.discord_webhook_url()

  # --- Feature Flags ---

  @doc """
  Gets the current debug logging status.
  """
  def debug_logging_enabled?, do: Config.debug_logging_enabled?()

  @doc """
  Enables debug logging.
  """
  def enable_debug_logging, do: Config.enable_debug_logging()

  @doc """
  Disables debug logging.
  """
  def disable_debug_logging, do: Config.disable_debug_logging()

  @doc """
  Sets debug logging state.
  """
  def set_debug_logging(state), do: Config.set_debug_logging(state)

  @doc """
  Gets the current dev mode status.
  """
  def dev_mode?, do: Config.dev_mode?()

  @doc """
  Gets the current notification features.
  """
  def notification_features, do: Config.notification_features()

  @doc """
  Checks if a notification feature is enabled.
  """
  def notification_feature_enabled?(flag), do: Config.notification_feature_enabled?(flag)

  @doc """
  Gets the current features.
  """
  def features, do: Config.features()

  @doc """
  Checks if a feature is enabled.
  """
  def feature_enabled?(flag), do: Config.feature_enabled?(flag)

  @doc """
  Gets the current status messages enabled status.
  """
  def status_messages_enabled?, do: Config.status_messages_enabled?()

  @doc """
  Gets the current track kspace status.
  """
  def track_kspace?, do: Config.track_kspace?()

  @doc """
  Gets the current tracked systems notifications enabled status.
  """
  def tracked_systems_notifications_enabled?, do: Config.tracked_systems_notifications_enabled?()

  @doc """
  Gets the current tracked characters notifications enabled status.
  """
  def tracked_characters_notifications_enabled?,
    do: Config.tracked_characters_notifications_enabled?()

  @doc """
  Gets the current character tracking enabled status.
  """
  def character_tracking_enabled?, do: Config.character_tracking_enabled?()

  @doc """
  Gets the current system tracking enabled status.
  """
  def system_tracking_enabled?, do: Config.system_tracking_enabled?()

  @doc """
  Gets the current status messages disabled status.
  """
  def status_messages_disabled?, do: Config.status_messages_disabled?()

  @doc """
  Gets the current track kspace systems status.
  """
  def track_kspace_systems?, do: Config.track_kspace_systems?()

  # --- Cache Configuration ---

  @doc """
  Gets the current cache directory.
  """
  def cache_dir, do: Config.cache_dir()

  @doc """
  Gets the current cache name.
  """
  def cache_name, do: Config.cache_name()

  # --- Web Server Configuration ---

  @doc """
  Gets the current port.
  """
  def port, do: Config.port()

  @doc """
  Gets the current host.
  """
  def host, do: Config.host()

  @doc """
  Gets the current scheme.
  """
  def scheme, do: Config.scheme()

  @doc """
  Gets the current public URL.
  """
  def public_url, do: Config.public_url()

  # --- API Configuration ---

  @doc """
  Gets the current API token.
  """
  def api_token, do: Config.api_token()

  @doc """
  Gets the current API key.
  """
  def api_key, do: Config.api_key()

  @doc """
  Gets the current API base URL.
  """
  def api_base_url, do: Config.api_base_url()

  @doc """
  Gets the current notifier API token.
  """
  def notifier_api_token, do: Config.notifier_api_token()

  # --- General Configuration ---

  @doc """
  Gets the current environment variable.
  """
  def get_env(key, default \\ nil), do: Config.get_env(key, default)

  # --- Application Statistics ---

  @doc """
  Gets all current statistics.
  """
  def get_all_stats, do: Stats.get_stats()

  @doc """
  Increments a counter statistic for the given type.
  Types can be :kill, :system, :character, etc.
  """
  def increment_counter(type), do: Stats.increment(type)
end
