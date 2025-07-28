defmodule WandererNotifier.Shared.Config do
  @moduledoc """
  Simplified configuration module that replaces the complex macro-based system.

  This module provides direct access to application configuration without the overhead
  of schemas, validators, or macro-generated functions. All configuration is accessed
  through simple functions that call Application.get_env/3 directly.
  """

  @behaviour WandererNotifier.Shared.Config.ConfigBehaviour

  # ══════════════════════════════════════════════════════════════════════════════
  # Core Configuration Access
  # ══════════════════════════════════════════════════════════════════════════════

  @doc """
  Gets a configuration value with an optional default.
  """
  def get(key, default \\ nil) do
    Application.get_env(:wanderer_notifier, key, default)
  end

  @doc "Legacy alias for get/2"
  def get_env(key, default \\ nil), do: get(key, default)

  @doc "Required by behavior - returns this config module"
  @impl true
  def config_module, do: __MODULE__

  # ══════════════════════════════════════════════════════════════════════════════
  # Feature Flags (Most commonly used)
  # ══════════════════════════════════════════════════════════════════════════════

  @impl true
  def notifications_enabled?, do: get(:notifications_enabled, true)

  @impl true
  def kill_notifications_enabled?, do: get(:kill_notifications_enabled, true)

  @impl true
  def system_notifications_enabled?, do: get(:system_notifications_enabled, true)

  @impl true
  def character_notifications_enabled?, do: get(:character_notifications_enabled, true)

  def status_messages_enabled?, do: get(:status_messages_enabled, false)

  def voice_participant_notifications_enabled?,
    do: get(:voice_participant_notifications_enabled, true)

  def fallback_to_here_enabled?, do: get(:fallback_to_here_enabled, false)
  def test_mode_enabled?, do: get(:test_mode_enabled, false)
  def priority_systems_only?, do: get(:priority_systems_only, false)
  def debug_logging_enabled?, do: get(:debug_logging_enabled, false)
  def schedulers_enabled?, do: get(:schedulers_enabled, false)
  def dev_mode?, do: get(:dev_mode, false)
  def telemetry_logging_enabled?, do: get(:telemetry_logging_enabled, false)
  def character_tracking_enabled?, do: get(:character_tracking_enabled, true)
  def system_tracking_enabled?, do: get(:system_tracking_enabled, true)

  def feature_enabled?(flag), do: get(flag, false)

  # ══════════════════════════════════════════════════════════════════════════════
  # Discord Configuration (Heavily used)
  # ══════════════════════════════════════════════════════════════════════════════

  def discord_bot_token, do: get(:discord_bot_token)
  def discord_application_id, do: get(:discord_application_id)
  def discord_guild_id, do: get(:discord_guild_id)
  def discord_webhook_url, do: get(:discord_webhook_url)
  def discord_channel_id, do: get(:discord_channel_id)

  # Channel specific functions
  def discord_system_channel_id, do: get(:discord_system_channel_id) || discord_channel_id()
  def discord_character_channel_id, do: get(:discord_character_channel_id) || discord_channel_id()

  def discord_system_kill_channel_id,
    do: get(:discord_system_kill_channel_id) || discord_channel_id()

  def discord_character_kill_channel_id,
    do: get(:discord_character_kill_channel_id) || discord_channel_id()

  def discord_charts_channel_id, do: get(:discord_charts_channel_id) || discord_channel_id()
  def discord_kill_channel_id, do: get(:discord_kill_channel_id) || discord_channel_id()

  # ══════════════════════════════════════════════════════════════════════════════
  # Map/Wanderer Configuration
  # ══════════════════════════════════════════════════════════════════════════════

  def map_token, do: get(:map_token)
  def map_csrf_token, do: get(:map_csrf_token)
  def map_api_key, do: get(:map_api_key)
  def map_url, do: get(:map_url)
  def map_name, do: get(:map_name)
  # Alias
  def map_slug, do: map_name()

  # ══════════════════════════════════════════════════════════════════════════════
  # API Configuration
  # ══════════════════════════════════════════════════════════════════════════════

  def api_token, do: get(:api_token)
  def api_key, do: get(:api_key)
  # Alias
  def notifier_api_token, do: api_token()
  def license_key, do: get(:license_key)
  def license_manager_api_key, do: get(:license_manager_api_key)
  def license_manager_api_url, do: get(:license_manager_api_url, "https://lm.wanderer.ltd")

  # ══════════════════════════════════════════════════════════════════════════════
  # Server Configuration
  # ══════════════════════════════════════════════════════════════════════════════

  def port, do: get(:port, 4000)
  def host, do: get(:host, "localhost")
  def scheme, do: get(:scheme, "http")
  def api_base_url, do: get(:api_base_url, "http://localhost:4000/api")
  def public_url, do: get(:public_url)
  def notification_service_base_url, do: get(:notification_service_base_url)

  # ══════════════════════════════════════════════════════════════════════════════
  # Timing and Intervals
  # ══════════════════════════════════════════════════════════════════════════════

  def deduplication_ttl, do: get(:deduplication_ttl, 1800)
  def min_kill_value, do: get(:min_kill_value, 0)
  def max_notifications_per_minute, do: get(:max_notifications_per_minute, 10)
  def static_info_ttl, do: get(:static_info_ttl, 3600)
  def character_update_scheduler_interval, do: get(:character_update_scheduler_interval, 30_000)
  def system_update_scheduler_interval, do: get(:system_update_scheduler_interval, 30_000)
  def license_refresh_interval, do: get(:license_refresh_interval, 1_200_000)
  def characters_cache_ttl, do: get(:characters_cache_ttl, 300)
  def kill_dedup_ttl, do: get(:kill_dedup_ttl, 600)
  def systems_cache_ttl, do: get(:systems_cache_ttl, 3600)

  # Service intervals
  def service_status_interval, do: get(:service_status_interval, 3_600_000)
  def killmail_retention_interval, do: get(:killmail_retention_interval, 600_000)
  def cache_check_interval, do: get(:cache_check_interval, 120_000)
  def cache_sync_interval, do: get(:cache_sync_interval, 180_000)
  def cache_cleanup_interval, do: get(:cache_cleanup_interval, 600_000)

  # ══════════════════════════════════════════════════════════════════════════════
  # Cache Configuration
  # ══════════════════════════════════════════════════════════════════════════════

  def cache_dir, do: get(:cache_dir, "/app/data/cache")
  def cache_name, do: get(:cache_name, :wanderer_notifier_cache)

  # ══════════════════════════════════════════════════════════════════════════════
  # External Service URLs
  # ══════════════════════════════════════════════════════════════════════════════

  def wanderer_kills_url, do: get(:wanderer_kills_url, "http://host.docker.internal:4004")
  def websocket_url, do: get(:websocket_url, "ws://host.docker.internal:4004")

  # ══════════════════════════════════════════════════════════════════════════════
  # System State
  # ══════════════════════════════════════════════════════════════════════════════

  def service_up?, do: get(:service_up, true)
  def telemetry_logging?, do: get(:telemetry_logging, false)

  # ══════════════════════════════════════════════════════════════════════════════
  # Utility Functions
  # ══════════════════════════════════════════════════════════════════════════════

  def version, do: get(:version, "unknown")

  def features do
    %{
      notifications_enabled: notifications_enabled?(),
      kill_notifications_enabled: kill_notifications_enabled?(),
      system_notifications_enabled: system_notifications_enabled?(),
      character_notifications_enabled: character_notifications_enabled?(),
      status_messages_enabled: status_messages_enabled?(),
      debug_logging_enabled: debug_logging_enabled?()
    }
  end

  def notification_features, do: features()
  def notification_feature_enabled?(flag), do: feature_enabled?(flag)

  # Environment variable helpers for complex lookups
  def notification_dedup_ttl_env do
    case System.get_env("NOTIFICATION_DEDUP_TTL") do
      nil -> deduplication_ttl()
      "" -> deduplication_ttl()
      value -> String.to_integer(value)
    end
  rescue
    _ -> deduplication_ttl()
  end

  # Debug controls
  def enable_debug_logging do
    Application.put_env(:wanderer_notifier, :debug_logging_enabled, true)
  end

  def disable_debug_logging do
    Application.put_env(:wanderer_notifier, :debug_logging_enabled, false)
  end

  def set_debug_logging(state) do
    Application.put_env(:wanderer_notifier, :debug_logging_enabled, state)
  end

  # ══════════════════════════════════════════════════════════════════════════════
  # ConfigBehaviour Implementation (Required by behavior)
  # ══════════════════════════════════════════════════════════════════════════════

  @impl true
  def get_notification_setting(type, key) do
    case {type, key} do
      {:kill, :enabled} -> {:ok, kill_notifications_enabled?()}
      {:system, :enabled} -> {:ok, system_notifications_enabled?()}
      {:character, :enabled} -> {:ok, character_notifications_enabled?()}
      _ -> {:error, :unknown_setting}
    end
  end

  @impl true
  def get_config do
    %{
      notifications: %{
        enabled: notifications_enabled?(),
        kill: %{enabled: kill_notifications_enabled?(), min_value: min_kill_value()},
        system: %{enabled: system_notifications_enabled?()},
        character: %{enabled: character_notifications_enabled?()}
      },
      features: features()
    }
  end

  # Module configuration for dependency injection
  @impl true
  def deduplication_module do
    get(:deduplication_module, WandererNotifier.Domains.Notifications.CacheImpl)
  end

  @impl true
  def system_track_module do
    get(:system_track_module, WandererNotifier.Domains.Tracking.Entities.System)
  end

  @impl true
  def character_track_module do
    get(:character_track_module, WandererNotifier.Domains.Tracking.Entities.Character)
  end

  @impl true
  def notification_determiner_module do
    get(:notification_determiner_module, WandererNotifier.Domains.Notifications.Determiner)
  end

  @impl true
  def killmail_enrichment_module do
    get(:killmail_enrichment_module, WandererNotifier.Domains.Killmail.Enrichment)
  end

  @impl true
  def killmail_notification_module do
    get(
      :killmail_notification_module,
      WandererNotifier.Domains.Notifications.KillmailNotification
    )
  end
end
