defmodule WandererNotifier.Config do
  @moduledoc """
  Centralized configuration access for WandererNotifier.

  Provides grouped functions for:
    - General app config
    - Map settings
    - Debug/logging
    - Notifications
    - Features
    - Cache
    - License
    - Web/server
    - API
  """
  @behaviour WandererNotifier.Config.ConfigBehaviour

  alias WandererNotifier.Config.Utils

  # Get the env provider from application config, defaulting to SystemEnvProvider
  defp env_provider do
    Application.get_env(
      :wanderer_notifier,
      :env_provider,
      WandererNotifier.Config.SystemEnvProvider
    )
  end

  # --- General ENV helpers ---
  def fetch!(key), do: env_provider().fetch_env!(key)
  def fetch(key, default \\ nil), do: env_provider().get_env(key, default)
  def fetch_int(key, default), do: fetch(key) |> Utils.parse_int(default)

  # --- General Application config ---
  def get(key, default \\ nil), do: Application.get_env(:wanderer_notifier, key, default)

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

  # --- TTL Configuration ---
  @doc """
  Returns the TTL for notification deduplication in seconds.
  Defaults to 3600 seconds (1 hour) if not configured.
  Can be configured via the :dedup_ttl environment variable.
  """
  def notification_dedup_ttl do
    # Get from environment variable first, then fall back to application config
    case env_provider().get_env("NOTIFICATION_DEDUP_TTL") do
      nil ->
        Application.get_env(:wanderer_notifier, :dedup_ttl, 3600)

      ttl ->
        Utils.parse_int(ttl, 3600)
    end
  end

  @doc """
  Returns the TTL for static information caching in seconds.
  """
  def static_info_ttl, do: Application.get_env(:wanderer_notifier, :static_info_ttl, 3600)

  # --- Version access ---
  @doc """
  Returns the application version string.
  """
  def version do
    WandererNotifier.Config.Version.version()
  end

  @doc """
  Returns detailed version information.
  """
  def version_info do
    WandererNotifier.Config.Version.version_info()
  end

  # --- Map config ---
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

  def map_token do
    value = get(:map_token)
    value
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

  def map_csrf_token, do: get(:map_csrf_token)

  def map_slug do
    # Slug = map_name (parsed or explicit)
    map_name()
  end

  def map_api_key, do: get(:map_api_key, "")

  # --- Debug config ---
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

  # --- Notification config ---
  def discord_channel_id, do: get(:discord_channel_id)
  def discord_system_kill_channel_id, do: get(:discord_system_kill_channel_id)
  def discord_character_kill_channel_id, do: get(:discord_character_kill_channel_id)
  def discord_system_channel_id, do: get(:discord_system_channel_id)
  def discord_character_channel_id, do: get(:discord_character_channel_id)
  def discord_charts_channel_id, do: get(:discord_charts_channel_id)
  def discord_bot_token, do: get(:discord_bot_token)
  def discord_webhook_url, do: get(:discord_webhook_url)

  def discord_application_id, do: get(:discord_application_id)

  def notification_features, do: get(:features, %{})
  def notification_feature_enabled?(flag), do: Map.get(notification_features(), flag, false)
  def min_kill_value, do: get(:min_kill_value, 0)
  def max_notifications_per_minute, do: get(:max_notifications_per_minute, 10)
  def discord_kill_channel_id, do: get(:discord_kill_channel_id)

  @doc """
  Returns whether chain kills mode is enabled.
  """
  def chain_kills_mode? do
    case Application.get_env(:wanderer_notifier, :config) do
      nil -> false
      mod -> mod.chain_kills_mode?()
    end
  end

  @doc """
  Returns whether rich notifications are enabled.
  """
  def rich_notifications_enabled? do
    case Application.get_env(:wanderer_notifier, :config) do
      nil -> false
      mod -> mod.rich_notifications_enabled?()
    end
  end

  @doc """
  Returns whether feature flags are enabled.
  """
  def feature_flags_enabled? do
    case Application.get_env(:wanderer_notifier, :config) do
      nil -> false
      mod -> mod.feature_flags_enabled?()
    end
  end

  def character_exclude_list do
    get(:character_exclude_list, "") |> Utils.parse_comma_list()
  end

  # --- Features ---
  @default_features [
    notifications_enabled: true,
    kill_notifications_enabled: true,
    system_notifications_enabled: true,
    character_notifications_enabled: true,
    status_messages_enabled: false,
    character_tracking_enabled: true,
    system_tracking_enabled: true,
    test_mode_enabled: false
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

  @impl true
  @spec notifications_enabled?() :: boolean()
  def notifications_enabled?, do: feature_enabled?(:notifications_enabled)

  @impl true
  @spec kill_notifications_enabled?() :: boolean()
  def kill_notifications_enabled?, do: feature_enabled?(:kill_notifications_enabled)

  @impl true
  @spec system_notifications_enabled?() :: boolean()
  def system_notifications_enabled?, do: feature_enabled?(:system_notifications_enabled)

  @impl true
  @spec character_notifications_enabled?() :: boolean()
  def character_notifications_enabled?, do: feature_enabled?(:character_notifications_enabled)

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

  def status_messages_enabled?, do: feature_enabled?(:status_messages_enabled)

  # Tracking is always enabled - users can only control notifications
  def character_tracking_enabled?, do: true
  def system_tracking_enabled?, do: true

  # --- Cache ---
  def cache_dir, do: get(:cache_dir, "/app/data/cache")
  def cache_name, do: get(:cache_name, :wanderer_notifier_cache)

  # --- License ---
  def license_key, do: get(:license_key)
  def license_manager_api_url, do: get(:license_manager_api_url, "https://lm.wanderer.ltd")
  def license_manager_api_key, do: get(:license_manager_api_key)

  # --- Web/server ---
  def port, do: get(:port, 4000) |> Utils.parse_port()
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

  # --- Module Dependencies ---
  @doc "Returns the HTTP client module to use."
  def http_client, do: get(:http_client, WandererNotifier.Http)

  @doc "Returns the ESI service module to use."
  def esi_service, do: get(:esi_service, WandererNotifier.ESI.Service)

  @doc "Returns the notification service module to use."
  def notification_service,
    do: get(:notification_service, WandererNotifier.Notifications.NotificationService)

  @doc "Returns the Discord notifier module to use."
  def discord_notifier, do: get(:discord_notifier, WandererNotifier.Notifiers.Discord.Notifier)

  @doc "Returns the killmail notification module to use."
  @impl true
  @spec killmail_notification_module() :: module()
  def killmail_notification_module,
    do: get(:killmail_notification_module, WandererNotifier.Notifications.KillmailNotification)

  @doc "Returns the config module to use."
  @impl true
  @spec config_module() :: module()
  def config_module, do: get(:config_module, __MODULE__)

  @doc "Returns the character track module to use."
  @impl true
  @spec character_track_module() :: module()
  def character_track_module, do: get(:character_track_module, WandererNotifier.Map.MapCharacter)

  @doc "Returns the system track module to use."
  @impl true
  @spec system_track_module() :: module()
  def system_track_module, do: get(:system_track_module, WandererNotifier.Map.MapSystem)

  @doc "Returns the deduplication module to use."
  @impl true
  @spec deduplication_module() :: module()
  def deduplication_module,
    do: get(:deduplication_module, WandererNotifier.Notifications.Deduplication.CacheImpl)

  @doc "Returns the notification determiner module to use."
  @impl true
  @spec notification_determiner_module() :: module()
  def notification_determiner_module,
    do: get(:notification_determiner_module, WandererNotifier.Notifications.Determiner.Kill)

  @doc "Returns the killmail enrichment module to use."
  @impl true
  @spec killmail_enrichment_module() :: module()
  def killmail_enrichment_module,
    do: get(:killmail_enrichment_module, WandererNotifier.Killmail.Enrichment)

  @doc "Returns the notification dispatcher module to use."
  @impl true
  @spec notification_dispatcher_module() :: module()
  def notification_dispatcher_module,
    do: get(:notification_dispatcher_module, WandererNotifier.Notifications.Dispatcher)

  # --- Telemetry ---
  @doc "Returns whether telemetry logging is enabled."
  def telemetry_logging_enabled?, do: get(:telemetry_logging, false)

  # --- Schedulers ---
  @doc "Returns whether schedulers are enabled."
  def schedulers_enabled?, do: get(:schedulers_enabled, false)

  # --- WebSocket Configuration ---
  @doc "Returns the WebSocket URL for the external killmail service."
  def websocket_url, do: fetch("WEBSOCKET_URL", "ws://host.docker.internal:4004")

  # --- Service URLs ---
  @doc "Returns the notification service base URL."
  def notification_service_base_url, do: get(:notification_service_base_url)

  # --- Service Status ---
  @doc "Returns whether the service is up."
  def service_up?, do: get(:service_up, true)

  # --- Deduplication TTL ---
  @doc "Returns the deduplication TTL in seconds."
  def deduplication_ttl, do: get(:deduplication_ttl, 3600)

  # --- Timings and Intervals ---
  @doc "Returns the character update scheduler interval in ms."
  def character_update_scheduler_interval, do: get(:character_update_scheduler_interval, 30_000)

  @doc "Returns the system update scheduler interval in ms."
  def system_update_scheduler_interval, do: get(:system_update_scheduler_interval, 30_000)

  @doc "Returns the license refresh interval in ms."
  def license_refresh_interval, do: get(:license_refresh_interval, 1_200_000)

  # --- Cache TTLs ---
  @doc "Returns the characters cache TTL in seconds."
  def characters_cache_ttl, do: get(:characters_cache_ttl, 300)
  def kill_dedup_ttl, do: get(:kill_dedup_ttl, 600)

  # --- Map Debug Settings ---
  @doc """
  Returns a map of debug-related map config.
  Useful for troubleshooting map API issues.
  """
  def map_debug_settings do
    %{
      debug_logging_enabled: debug_logging_enabled?(),
      map_url: map_url(),
      map_name: map_name(),
      map_token: map_token()
    }
  end

  # --- Map Config Diagnostics ---
  @doc """
  Returns a diagnostic map of all map-related configuration.
  Useful for troubleshooting map API issues.
  """
  def map_config_diagnostics do
    _url = map_url()
    token = map_token()
    base_url = map_url()
    name = map_name()

    %{
      map_url: base_url,
      map_url_present: base_url |> Utils.nil_or_empty?() |> Kernel.not(),
      map_url_explicit: get(:map_url) |> Utils.nil_or_empty?() |> Kernel.not(),
      map_name: name,
      map_name_present: name |> Utils.nil_or_empty?() |> Kernel.not(),
      map_name_explicit: get(:map_name) |> Utils.nil_or_empty?() |> Kernel.not(),
      map_token: token,
      map_token_present: !Utils.nil_or_empty?(token),
      map_token_length: if(token, do: String.length(token), else: 0),
      map_slug: map_slug(),
      map_slug_present: !Utils.nil_or_empty?(map_slug()),
      base_map_url: base_map_url(),
      base_map_url_present: !Utils.nil_or_empty?(base_map_url()),
      system_tracking_enabled: system_tracking_enabled?()
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
  def service_status_interval, do: get(:service_status_interval, 3_600_000)

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

  # Returns the base map URL
  def base_map_url do
    map_url()
  end
end
