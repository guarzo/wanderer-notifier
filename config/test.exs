import Config

# Environment-specific configuration
config :wanderer_notifier,
  test_env: true,
  env: :test,
  disable_status_messages: true,
  cache_name: :wanderer_cache

# Test mode configuration
config :nostrum, token: "test_discord_token"

# WandererNotifier test configuration
config :wanderer_notifier,
  discord: %{
    bot_token: "test_token",
    channel_id: "123456789"
  },
  map_url: "https://example.com",
  map_token: "test_map_token",
  test_mode: true,
  minimal_test: System.get_env("MINIMAL_TEST") == "true",
  features: %{
    notifications_enabled: true,
    character_notifications_enabled: true,
    system_notifications_enabled: true,
    kill_notifications_enabled: true,
    character_tracking_enabled: true,
    system_tracking_enabled: true,
    tracked_systems_notifications_enabled: true,
    tracked_characters_notifications_enabled: true,
    status_messages_disabled: true,
    track_kspace_systems: true
  },
  cache_repository: WandererNotifier.Cache.CachexImpl,
  esi_service: WandererNotifier.ESI.ServiceMock

# Logger configuration for tests
config :logger, level: :warning
config :logger, :console, format: "[$level] $message\n"

# Configure the test environment
config :wanderer_notifier,
  schedulers_enabled: false,
  scheduler_supervisor_enabled: false

# Configure the logger (combined configuration)
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Configure the cache
config :wanderer_notifier, :cache,
  backend: WandererNotifier.Cache.CachexImpl,
  ttl: 3600

# Configure the ESI service
config :wanderer_notifier, :esi, service: WandererNotifier.ESI.ServiceMock

# Configure the notification service
config :wanderer_notifier, :notifications, service: WandererNotifier.Notifiers.TestNotifier

# Configure the kill determiner
config :wanderer_notifier, :kill_determiner,
  service: WandererNotifier.Notifications.Determiner.KillMock

# Configure Mox
config :mox, :global, true
