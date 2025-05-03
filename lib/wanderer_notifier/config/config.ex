defmodule WandererNotifier.Config do
  @moduledoc """
  Centralized configuration access for WandererNotifier.

  Provides grouped functions for:
    - General app config
    - Map settings
    - Debug/logging
    - Notifications
    - Features
    - Websocket
    - Cache
    - License
    - Web/server
    - API
  """
  # --- General ENV helpers ---
  def fetch!(key), do: System.get_env(key) || raise("Missing ENV: #{key}")
  def fetch(key, default \\ nil), do: System.get_env(key) || default
  def fetch_int(key, default), do: fetch(key) |> parse_int(default)
  defp parse_int(nil, default), do: default

  defp parse_int(str, default) do
    case Integer.parse(str) do
      {i, _} -> i
      :error -> default
    end
  end

  # --- General Application config ---
  def get(key, default \\ nil), do: Application.get_env(:wanderer_notifier, key, default)

  # --- Map config ---
  def map_url do
    raise "map_url/0 is deprecated. Use map_url_with_name/0 and parse as needed."
  end

  def map_token do
    value = get(:map_token)
    IO.inspect(value, label: "[CONFIG DEBUG] map_token")
    value
  end

  def map_name do
    value = get(:map_name)
    value
  end

  def map_url_with_name, do: get(:map_url_with_name)
  def map_csrf_token, do: get(:map_csrf_token)

  def map_slug do
    url = map_url_with_name()
    uri = URI.parse(url || "")
    slug = uri.path |> String.trim("/") |> String.split("/") |> List.last()
    IO.inspect(slug, label: "[CONFIG DEBUG] map_slug")
    slug
  end

  def map_api_key, do: get(:map_api_key, "")
  def static_info_cache_ttl, do: get(:static_info_cache_ttl, 3600)

  # --- Debug config ---
  def debug_logging_enabled?, do: get(:debug_logging_enabled, false)
  def toggle_debug_logging, do: set(:debug_logging_enabled, !debug_logging_enabled?())
  def set_debug_logging(state) when is_boolean(state), do: set(:debug_logging_enabled, state)
  defp set(key, value), do: Application.put_env(:wanderer_notifier, key, value)

  # --- Notification config ---
  def discord_channel_id, do: get(:discord_channel_id)
  def discord_system_kill_channel_id, do: get(:discord_system_kill_channel_id)
  def discord_character_kill_channel_id, do: get(:discord_character_kill_channel_id)
  def discord_system_channel_id, do: get(:discord_system_channel_id)
  def discord_character_channel_id, do: get(:discord_character_channel_id)
  def discord_charts_channel_id, do: get(:discord_charts_channel_id)
  def discord_bot_token, do: get(:discord_bot_token)
  def discord_webhook_url, do: get(:discord_webhook_url)
  def notification_features, do: get(:features, %{})
  def notification_feature_enabled?(flag), do: Map.get(notification_features(), flag, false)
  def min_kill_value, do: get(:min_kill_value, 0)
  def max_notifications_per_minute, do: get(:max_notifications_per_minute, 10)

  def character_exclude_list do
    get(:character_exclude_list, "") |> String.split(",", trim: true) |> Enum.map(&String.trim/1)
  end

  # --- Features ---
  def features, do: get(:features, %{})
  def feature_enabled?(flag), do: Map.get(features(), flag, false)
  def notifications_enabled?, do: feature_enabled?(:notifications_enabled)
  def character_notifications_enabled?, do: feature_enabled?(:character_notifications_enabled)
  def system_notifications_enabled?, do: feature_enabled?(:system_notifications_enabled)
  def kill_notifications_enabled?, do: feature_enabled?(:kill_notifications_enabled)
  def character_tracking_enabled?, do: feature_enabled?(:character_tracking_enabled)
  def system_tracking_enabled?, do: feature_enabled?(:system_tracking_enabled)

  def tracked_systems_notifications_enabled?,
    do: feature_enabled?(:tracked_systems_notifications_enabled)

  def tracked_characters_notifications_enabled?,
    do: feature_enabled?(:tracked_characters_notifications_enabled)

  def status_messages_disabled?, do: feature_enabled?(:status_messages_disabled)
  def track_kspace_systems?, do: feature_enabled?(:track_kspace_systems)

  # --- Websocket ---
  def websocket_config, do: get(:websocket, %{})
  def websocket_enabled?, do: Map.get(websocket_config(), :enabled, true)
  def websocket_reconnect_delay, do: Map.get(websocket_config(), :reconnect_delay, 5000)
  def websocket_max_reconnects, do: Map.get(websocket_config(), :max_reconnects, 20)
  def websocket_reconnect_window, do: Map.get(websocket_config(), :reconnect_window, 3600)

  # --- Cache ---
  def cache_dir, do: get(:cache_dir, "/app/data/cache")
  def cache_name, do: get(:cache_name, :wanderer_notifier_cache)

  # --- License ---
  def license_key, do: get(:license_key)
  def license_manager_api_url, do: get(:license_manager_api_url)
  def license_manager_api_key, do: get(:license_manager_api_key)

  # --- Web/server ---
  def port, do: get(:port, 4000)
  def host, do: get(:host, "localhost")
  def scheme, do: get(:scheme, "http")
  def public_url, do: get(:public_url)

  # --- API ---
  def api_token, do: get(:api_token)
  def api_key, do: get(:api_key)
  def api_base_url, do: get(:api_base_url, "http://localhost:4000/api")

  # --- Utility ---
  def get_env(key, default \\ nil), do: get(key, default)

  # --- Limits ---
  @doc "Returns a map of system/character/notification limits."
  def get_all_limits do
    %{
      tracked_systems: get(:max_tracked_systems, 1000),
      tracked_characters: get(:max_tracked_characters, 1000),
      notification_history: get(:max_notification_history, 1000)
    }
  end

  # --- Notification API Token ---
  @doc "Returns the notifier API token."
  def notifier_api_token, do: api_token()

  # --- Test Mode ---
  @doc "Returns true if test mode is enabled."
  def test_mode_enabled?, do: feature_enabled?(:test_mode_enabled)

  # --- Timings and Intervals ---
  @doc "Returns the character update scheduler interval in ms."
  def character_update_scheduler_interval, do: get(:character_update_scheduler_interval, 60_000)

  @doc "Returns the system update scheduler interval in ms."
  def system_update_scheduler_interval, do: get(:system_update_scheduler_interval, 60_000)

  @doc "Returns the license refresh interval in ms."
  def license_refresh_interval, do: get(:license_refresh_interval, 600_000)

  # --- Cache TTLs ---
  @doc "Returns the characters cache TTL in seconds."
  def characters_cache_ttl, do: get(:characters_cache_ttl, 300)

  # --- Tracking Data Feature ---
  @doc "Returns true if tracking data should be loaded."
  def should_load_tracking_data?, do: feature_enabled?(:should_load_tracking_data)

  # --- Map Debug Settings ---
  @doc "Returns a map of debug-related map config."
  def map_debug_settings do
    %{
      debug_logging_enabled: debug_logging_enabled?(),
      map_url_with_name: map_url_with_name(),
      map_token: map_token(),
      map_name: map_name()
    }
  end

  # --- API Base URL ---
  @doc "Returns the API base URL."
  def get_api_base_url do
    value = api_base_url()
    value
  end

  # --- Scheduler/Timing Accessors ---
  @doc "Returns the service status interval in ms."
  def service_status_interval, do: get(:service_status_interval, 300_000)

  @doc "Returns the killmail retention interval in ms."
  def killmail_retention_interval, do: get(:killmail_retention_interval, 600_000)

  @doc "Returns the cache check interval in ms."
  def cache_check_interval, do: get(:cache_check_interval, 120_000)

  @doc "Returns the cache sync interval in ms."
  def cache_sync_interval, do: get(:cache_sync_interval, 180_000)

  @doc "Returns the cache cleanup interval in ms."
  def cache_cleanup_interval, do: get(:cache_cleanup_interval, 600_000)

  # --- Cache TTLs ---
  @doc "Returns the systems cache TTL in seconds."
  def systems_cache_ttl, do: get(:systems_cache_ttl, 300)

  # Add a function to return the base URL portion of map_url_with_name
  def base_map_url do
    url = map_url_with_name()
    uri = URI.parse(url || "")
    base_url = "#{uri.scheme}://#{uri.host}#{if uri.port, do: ":#{uri.port}", else: ""}"
    base_url
  end
end
