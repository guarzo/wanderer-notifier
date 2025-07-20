defmodule WandererNotifier.Shared.Config do
  @moduledoc """
  Streamlined configuration module using the new Config.Helpers macros.

  This module replaces the 527-line Config module with a much more concise
  implementation using macro-generated accessors. This eliminates ~400-500
  lines of duplicate configuration code.
  """

  require WandererNotifier.Shared.Config.Helpers
  import WandererNotifier.Shared.Config.Helpers, except: [feature_enabled?: 1, get: 1, get: 2]
  alias WandererNotifier.Shared.Config.Utils

  @behaviour WandererNotifier.Shared.Config.ConfigBehaviour

  # Base configuration getter
  def get(key, default \\ nil), do: Application.get_env(:wanderer_notifier, key, default)

  # Required by behavior - returns this config module
  @impl true
  def config_module, do: __MODULE__

  # Generate simple configuration accessors
  defconfig(:simple, [
    :discord_bot_token,
    :discord_application_id,
    :discord_guild_id,
    :discord_webhook_url,
    :discord_channel_id,
    :map_token,
    :map_csrf_token,
    :map_api_key,
    :license_key,
    :license_manager_api_key,
    :api_token,
    :api_key,
    :public_url,
    :notification_service_base_url
  ])

  # Generate configuration accessors with defaults
  defconfig(:with_defaults, [
    {:port, 4000},
    {:host, "localhost"},
    {:scheme, "http"},
    {:api_base_url, "http://localhost:4000/api"},
    {:license_manager_api_url, "https://lm.wanderer.ltd"},
    {:cache_dir, "/app/data/cache"},
    {:cache_name, :wanderer_notifier_cache},
    {:min_kill_value, 0},
    {:max_notifications_per_minute, 10},
    {:static_info_ttl, 3600},
    {:dev_mode, false},
    {:service_up, true},
    {:deduplication_ttl, 3600},
    {:character_update_scheduler_interval, 30_000},
    {:system_update_scheduler_interval, 30_000},
    {:license_refresh_interval, 1_200_000},
    {:characters_cache_ttl, 300},
    {:kill_dedup_ttl, 600},
    {:service_status_interval, 3_600_000},
    {:killmail_retention_interval, 600_000},
    {:cache_check_interval, 120_000},
    {:cache_sync_interval, 180_000},
    {:cache_cleanup_interval, 600_000},
    {:systems_cache_ttl, 3600},
    {:schedulers_enabled, false},
    {:telemetry_logging, false}
  ])

  # Generate Discord channel accessors
  defconfig(:channels, [
    :discord_system_kill,
    :discord_character_kill,
    :discord_system,
    :discord_character,
    :discord_charts,
    :discord_kill,
    :discord_channel
  ])

  # Generate feature flag accessors
  defconfig(:features, [
    :notifications_enabled,
    :kill_notifications_enabled,
    :system_notifications_enabled,
    :character_notifications_enabled,
    :status_messages_enabled,
    :voice_participant_notifications_enabled,
    :fallback_to_here_enabled,
    :test_mode_enabled
  ])

  # Environment variable accessors (simplified for now)
  def websocket_url, do: fetch("WEBSOCKET_URL", "ws://host.docker.internal:4004")
  def notification_dedup_ttl_env, do: fetch_int("NOTIFICATION_DEDUP_TTL", 1800)

  # Custom transformation accessors (simplified for now)
  def character_exclude_list do
    get(:character_exclude_list, "") |> Utils.parse_comma_list()
  end

  # Advanced feature schema (simplified for now, features implemented manually below)

  # Configuration validation (simplified for now)

  # --- Complex Configuration Logic ---

  @impl true
  @spec get_config() :: map()
  def get_config do
    %{
      notifications_enabled: notifications_enabled?(),
      kill_notifications_enabled: kill_notifications_enabled?(),
      system_notifications_enabled: system_notifications_enabled?(),
      character_notifications_enabled: character_notifications_enabled?()
    }
  end

  @impl true
  @spec get_notification_setting(atom(), atom()) :: {:ok, boolean()} | {:error, term()}
  def get_notification_setting(type, key) do
    case Application.get_env(:wanderer_notifier, :config) do
      nil -> {:ok, true}
      mod -> mod.get_notification_setting(type, key)
    end
  end

  # Map configuration with complex fallback logic
  def map_url do
    # First try the explicit MAP_URL, then fall back to parsing from URL
    explicit_url = get(:map_url)

    case explicit_url do
      url when is_binary(url) and url != "" ->
        url

      _ ->
        # Fall back to base_map_url for backward compatibility
        base_map_url()
    end
  end

  def map_name do
    # First try the explicit MAP_NAME, then fall back to parsing from URL
    explicit_name = get(:map_name)

    if explicit_name && explicit_name != "" do
      explicit_name
    else
      # Parse `name` query param from map_url
      get(:map_url)
      |> Utils.parse_map_name_from_url()
    end
  end

  def map_slug do
    # Slug = map_name (parsed or explicit)
    map_name()
  end

  def base_map_url do
    map_url()
  end

  # Debug configuration with runtime state management
  def debug_logging_enabled?, do: get(:debug_logging_enabled, false)

  def enable_debug_logging,
    do: Application.put_env(:wanderer_notifier, :debug_logging_enabled, true)

  def disable_debug_logging,
    do: Application.put_env(:wanderer_notifier, :debug_logging_enabled, false)

  def set_debug_logging(state) when is_boolean(state),
    do: Application.put_env(:wanderer_notifier, :debug_logging_enabled, state)

  # Cache dev mode value at compile time
  @dev_mode Application.compile_env(:wanderer_notifier, :dev_mode, false)

  @doc """
  Returns whether the application is running in development mode.
  Used to enable more verbose logging and other development features.

  The value is cached at compile time for better performance.
  To change the value, you must recompile the module or restart the application.
  """
  def dev_mode?, do: @dev_mode

  # TTL Configuration with environment override
  @doc """
  Returns the TTL for notification deduplication in seconds.
  Defaults to 1800 seconds (30 minutes) if not configured.
  Can be configured via the :dedup_ttl environment variable.
  """
  def notification_dedup_ttl do
    # Get from environment variable first, then fall back to application config
    case env_provider().get_env("NOTIFICATION_DEDUP_TTL") do
      nil ->
        Application.get_env(:wanderer_notifier, :dedup_ttl, 1800)

      ttl ->
        Utils.parse_int(ttl, 1800)
    end
  end

  # Version access delegation
  def version do
    WandererNotifier.Shared.Config.Version.version()
  end

  def version_info do
    WandererNotifier.Shared.Config.Version.version_info()
  end

  # Feature management with caching
  @default_features [
    notifications_enabled: true,
    kill_notifications_enabled: true,
    system_notifications_enabled: true,
    character_notifications_enabled: true,
    status_messages_enabled: false,
    character_tracking_enabled: true,
    system_tracking_enabled: true,
    test_mode_enabled: false,
    voice_participant_notifications_enabled: false,
    fallback_to_here_enabled: true
  ]

  def features do
    # Get features from config and normalize to keyword list
    features_from_config = get(:features, %{})
    normalized = Utils.normalize_features(features_from_config)

    # Merge with defaults, config values take precedence
    Keyword.merge(@default_features, normalized)
  end

  @doc """
  Checks if a feature flag is enabled.

  This is the primary interface for checking feature flags.
  All feature checks should go through this function.

  ## Examples
      iex> feature_enabled?(:notifications_enabled)
      true

      iex> feature_enabled?(:unknown_feature)
      false
  """
  def feature_enabled?(flag) do
    Keyword.get(features(), flag, false)
  end

  # Advanced feature flag with caching
  @doc """
  Returns true if only priority systems should generate notifications.
  When enabled, regular (non-priority) systems will not generate notifications
  regardless of the system_notifications_enabled setting.

  This value is cached using persistent_term for performance.
  """
  @spec priority_systems_only?() :: boolean()
  def priority_systems_only? do
    case :persistent_term.get({__MODULE__, :priority_systems_only}, :not_cached) do
      :not_cached ->
        value = get(:priority_systems_only, false)
        :persistent_term.put({__MODULE__, :priority_systems_only}, value)
        value

      cached_value ->
        cached_value
    end
  end

  @doc """
  Refreshes the cached value for priority_systems_only.

  Call this function whenever the configuration changes to ensure
  the cached value stays in sync.
  """
  @spec refresh_priority_systems_only!() :: :ok
  def refresh_priority_systems_only! do
    value = get(:priority_systems_only, false)
    :persistent_term.put({__MODULE__, :priority_systems_only}, value)
    :ok
  end

  # Delegated feature flags
  # Always enabled
  def character_tracking_enabled?, do: true
  # Always enabled
  def system_tracking_enabled?, do: true

  # Additional feature flags
  def schedulers_enabled?, do: schedulers_enabled()
  def telemetry_logging_enabled?, do: telemetry_logging()

  # Complex notification logic delegation
  def chain_kills_mode? do
    case Application.get_env(:wanderer_notifier, :config) do
      nil -> false
      mod -> mod.chain_kills_mode?()
    end
  end

  def rich_notifications_enabled? do
    case Application.get_env(:wanderer_notifier, :config) do
      nil -> false
      mod -> mod.rich_notifications_enabled?()
    end
  end

  def feature_flags_enabled? do
    case Application.get_env(:wanderer_notifier, :config) do
      nil -> false
      mod -> mod.feature_flags_enabled?()
    end
  end

  def notification_features, do: get(:features, %{})
  def notification_feature_enabled?(flag), do: Map.get(notification_features(), flag, false)

  # Utility functions
  def get_env(key, default \\ nil), do: get(key, default)

  def get_all_limits do
    %{
      tracked_systems: get(:max_tracked_systems, 1000),
      tracked_characters: get(:max_tracked_characters, 1000),
      notification_history: get(:max_notification_history, 1000)
    }
  end

  def notifier_api_token, do: api_token()

  # Module dependency injection
  def http_client, do: get(:http_client, WandererNotifier.Http)
  def esi_service, do: get(:esi_service, WandererNotifier.Infrastructure.Adapters.ESI.Service)

  def notification_service,
    do: get(:notification_service, WandererNotifier.Domains.Notifications.NotificationService)

  def discord_notifier,
    do: get(:discord_notifier, WandererNotifier.Domains.Notifications.Notifiers.Discord.Notifier)

  @impl true
  @spec killmail_notification_module() :: module()
  def killmail_notification_module,
    do:
      get(
        :killmail_notification_module,
        WandererNotifier.Domains.Notifications.KillmailNotification
      )

  @impl true
  @spec character_track_module() :: module()
  def character_track_module,
    do: get(:character_track_module, WandererNotifier.Domains.CharacterTracking.Character)

  @impl true
  @spec system_track_module() :: module()
  def system_track_module, do: get(:system_track_module, WandererNotifier.Domains.SystemTracking.System)

  @impl true
  @spec deduplication_module() :: module()
  def deduplication_module,
    do: get(:deduplication_module, WandererNotifier.Domains.Notifications.Deduplication.CacheImpl)

  @impl true
  @spec notification_determiner_module() :: module()
  def notification_determiner_module,
    do:
      get(:notification_determiner_module, WandererNotifier.Domains.Notifications.Determiner.Kill)

  @impl true
  @spec killmail_enrichment_module() :: module()
  def killmail_enrichment_module,
    do: get(:killmail_enrichment_module, WandererNotifier.Domains.Killmail.Enrichment)


  # Discord configuration aggregation
  def discord_config do
    %{
      bot_token: discord_bot_token(),
      application_id: discord_application_id(),
      guild_id: discord_guild_id(),
      webhook_url: discord_webhook_url(),
      default_channel_id: discord_channel_id(),
      channels: channel_config(),
      notifier_module: discord_notifier()
    }
  end

  # Discord channel configuration aggregation
  def channel_config do
    %{
      system_kill: discord_system_kill_channel_id(),
      character_kill: discord_character_kill_channel_id(),
      system: discord_system_channel_id(),
      character: discord_character_channel_id(),
      charts: discord_charts_channel_id(),
      kill: discord_kill_channel_id(),
      channel: discord_channel_channel_id()
    }
  end

  # Map debug configuration aggregation
  def map_debug_settings do
    %{
      debug_logging_enabled: debug_logging_enabled?(),
      map_url: map_url(),
      map_name: map_name(),
      map_token: map_token()
    }
  end

  def map_config_diagnostics do
    token = map_token()
    base_url = map_url()
    name = map_name()

    %{
      map_url: base_url,
      map_url_present: not (is_nil(base_url) or base_url == ""),
      map_url_explicit: not (is_nil(get(:map_url)) or get(:map_url) == ""),
      map_token: token,
      map_token_present: not (is_nil(token) or token == ""),
      map_token_explicit: not (is_nil(get(:map_token)) or get(:map_token) == ""),
      map_name: name,
      map_name_present: not (is_nil(name) or name == ""),
      map_name_explicit: not (is_nil(get(:map_name)) or get(:map_name) == "")
    }
  end

  def get_api_base_url do
    value = api_base_url()
    value
  end

  # Private helper functions
  defp env_provider do
    Application.get_env(
      :wanderer_notifier,
      :env_provider,
      WandererNotifier.Shared.Config.SystemEnvProvider
    )
  end

  # General ENV helpers
  def fetch!(key), do: env_provider().fetch_env!(key)
  def fetch(key, default \\ nil), do: env_provider().get_env(key, default)
  def fetch_int(key, default), do: fetch(key) |> Utils.parse_int(default)
end
