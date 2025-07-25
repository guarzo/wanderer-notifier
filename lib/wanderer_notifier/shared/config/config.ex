defmodule WandererNotifier.Shared.Config do
  @moduledoc """
  Simplified configuration module using direct map access instead of macros.

  This replaces the macro-heavy approach with a simple map-based configuration
  system that's easier to understand and maintain.
  """

  alias WandererNotifier.Shared.Config.Utils

  @behaviour WandererNotifier.Shared.Config.ConfigBehaviour

  # Base configuration getter
  def get(key, default \\ nil), do: Application.get_env(:wanderer_notifier, key, default)

  # Required by behavior - returns this config module
  @impl true
  def config_module, do: __MODULE__

  # ══════════════════════════════════════════════════════════════════════════════
  # Configuration Maps (replaces macro generation)
  # ══════════════════════════════════════════════════════════════════════════════

  # Simple configuration keys (no defaults)
  @simple_config %{
    discord_bot_token: nil,
    discord_application_id: nil,
    discord_guild_id: nil,
    discord_webhook_url: nil,
    discord_channel_id: nil,
    map_token: nil,
    map_csrf_token: nil,
    map_api_key: nil,
    license_key: nil,
    license_manager_api_key: nil,
    api_token: nil,
    api_key: nil,
    public_url: nil,
    notification_service_base_url: nil
  }

  # Configuration with defaults
  @default_config %{
    port: 4000,
    host: "localhost",
    scheme: "http",
    api_base_url: "http://localhost:4000/api",
    license_manager_api_url: "https://lm.wanderer.ltd",
    cache_dir: "/app/data/cache",
    cache_name: :wanderer_notifier_cache,
    min_kill_value: 0,
    max_notifications_per_minute: 10,
    static_info_ttl: 3600,
    dev_mode: false,
    service_up: true,
    deduplication_ttl: 3600,
    character_update_scheduler_interval: 30_000,
    system_update_scheduler_interval: 30_000,
    license_refresh_interval: 1_200_000,
    characters_cache_ttl: 300,
    kill_dedup_ttl: 600,
    service_status_interval: 3_600_000,
    killmail_retention_interval: 600_000,
    cache_check_interval: 120_000,
    cache_sync_interval: 180_000,
    cache_cleanup_interval: 600_000,
    systems_cache_ttl: 3600,
    schedulers_enabled: false,
    telemetry_logging: false
  }

  # Feature flags with defaults
  @feature_flags %{
    notifications_enabled: true,
    kill_notifications_enabled: true,
    system_notifications_enabled: true,
    character_notifications_enabled: true,
    status_messages_enabled: false,
    voice_participant_notifications_enabled: true,
    fallback_to_here_enabled: false,
    test_mode_enabled: false
  }

  # Discord channel configurations
  @channel_config %{
    discord_system_kill: nil,
    discord_character_kill: nil,
    discord_system: nil,
    discord_character: nil,
    discord_charts: nil,
    discord_kill: nil,
    discord_channel: nil
  }

  # ══════════════════════════════════════════════════════════════════════════════
  # Accessor Functions (replaces macro-generated functions)
  # ══════════════════════════════════════════════════════════════════════════════

  # Simple config accessors
  for {key, _default} <- @simple_config do
    def unquote(key)(), do: get(unquote(key))
  end

  # Config with defaults accessors  
  for {key, default} <- @default_config do
    def unquote(key)(), do: get(unquote(key), unquote(default))
  end

  # Feature flag accessors (with ? suffix)
  for {key, _default} <- @feature_flags do
    func_name = String.to_atom("#{key}?")

    # Add @impl true for behavior callbacks
    if func_name in [
         :notifications_enabled?,
         :kill_notifications_enabled?,
         :system_notifications_enabled?,
         :character_notifications_enabled?
       ] do
      @impl true
    end

    def unquote(func_name)(), do: feature_enabled?(unquote(key))
  end

  # Channel accessors
  for {key, _default} <- @channel_config do
    func_name = String.to_atom("#{key}_channel_id")
    config_key = String.to_atom("#{key}_channel_id")
    def unquote(func_name)(), do: get(unquote(config_key))
  end

  # ══════════════════════════════════════════════════════════════════════════════
  # Specialized Functions
  # ══════════════════════════════════════════════════════════════════════════════

  # Environment variable accessors
  def websocket_url, do: fetch_env("WEBSOCKET_URL", "ws://host.docker.internal:4004")
  def notification_dedup_ttl_env, do: fetch_env_int("NOTIFICATION_DEDUP_TTL", 1800)

  # Custom transformation accessors
  def character_exclude_list do
    get(:character_exclude_list, [])
    |> case do
      list when is_list(list) -> list
      _ -> []
    end
  end

  def system_exclude_list do
    get(:system_exclude_list, [])
    |> case do
      list when is_list(list) -> list
      _ -> []
    end
  end

  # Feature flag helper
  def feature_enabled?(feature_key) do
    default = Map.get(@feature_flags, feature_key, false)
    env_key = feature_key |> Atom.to_string() |> String.upcase()

    case fetch_env(env_key) do
      nil -> get(feature_key, default)
      env_value -> Utils.parse_bool(env_value, default)
    end
  end

  # Map configuration helpers
  def map_url, do: get(:map_url)
  def map_name, do: get(:map_name)

  # Note: license_manager_api_url is already defined in @default_config

  # ══════════════════════════════════════════════════════════════════════════════
  # Behavior Implementation
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
        kill: %{
          enabled: kill_notifications_enabled?(),
          min_value: min_kill_value()
        },
        system: %{
          enabled: system_notifications_enabled?()
        },
        character: %{
          enabled: character_notifications_enabled?()
        }
      },
      features: %{
        notifications_enabled: notifications_enabled?(),
        kill_notifications_enabled: kill_notifications_enabled?(),
        system_notifications_enabled: system_notifications_enabled?(),
        character_notifications_enabled: character_notifications_enabled?(),
        status_messages_enabled: status_messages_enabled?(),
        voice_participant_notifications_enabled: voice_participant_notifications_enabled?(),
        fallback_to_here_enabled: fallback_to_here_enabled?(),
        test_mode_enabled: test_mode_enabled?()
      }
    }
  end

  # Module delegation helpers (for behavior compatibility)
  @impl true
  def deduplication_module,
    do: get(:deduplication_module, WandererNotifier.Domains.Notifications.CacheImpl)

  @impl true
  def system_track_module,
    do: get(:system_track_module, WandererNotifier.Domains.SystemTracking.System)

  @impl true
  def character_track_module,
    do: get(:character_track_module, WandererNotifier.Domains.CharacterTracking.Character)

  @impl true
  def notification_determiner_module,
    do:
      get(:notification_determiner_module, WandererNotifier.Domains.Notifications.Determiner.Kill)

  @impl true
  def killmail_enrichment_module,
    do: get(:killmail_enrichment_module, WandererNotifier.Domains.Killmail.Enrichment)

  @impl true
  def killmail_notification_module,
    do:
      get(
        :killmail_notification_module,
        WandererNotifier.Domains.Notifications.KillmailNotification
      )

  # Discord channel helpers
  def discord_channel_id_for(channel_type) do
    case channel_type do
      :main -> discord_channel_id()
      :system_kill -> discord_system_kill_channel_id() || discord_channel_id()
      :character_kill -> discord_character_kill_channel_id() || discord_channel_id()
      :system -> discord_system_channel_id() || discord_channel_id()
      :character -> discord_character_channel_id() || discord_channel_id()
      :charts -> discord_charts_channel_id() || discord_channel_id()
      :kill -> discord_kill_channel_id() || discord_channel_id()
      _ -> discord_channel_id()
    end
  end

  # Environment variable helpers
  defp fetch_env(key, default \\ nil) do
    System.get_env(key, default)
  end

  defp fetch_env_int(key, default) do
    case System.get_env(key) do
      nil -> default
      "" -> default
      value -> Utils.parse_int(value, default)
    end
  end
end
