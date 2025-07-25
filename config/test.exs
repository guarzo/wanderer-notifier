import Config

# Environment-specific configuration
config :wanderer_notifier,
  test_env: true,
  env: :test,
  disable_status_messages: true,
  chart_service_dir: System.get_env("CHART_SERVICE_DIR", "/workspace/chart-service")

# Test mode configuration
config :nostrum, token: "test_discord_token"

# WandererNotifier test configuration
config :wanderer_notifier,
  discord: %{
    bot_token: "test_token",
    channel_id: "123456789"
  },
  discord_application_id: "test_app_id",
  discord_bot_token: "test_token",
  map_url: "https://example.com",
  map_name: "testmap",
  map_token: "test_map_api_key",
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
  }

# Configure the test environment
config :wanderer_notifier,
  schedulers_enabled: false,
  scheduler_supervisor_enabled: false

# Configure the logger (simple format for tests)
config :logger, level: :debug

config :logger, :console,
  format: "$time [$level] $message $metadata\n",
  metadata: [:category],
  device: :standard_error

# Configure the cache - all cache settings in one place
config :wanderer_notifier,
  cache_name: :wanderer_cache_test,
  cache_adapter: Cachex

# Configure the ESI service
config :wanderer_notifier, :esi, service: WandererNotifier.ESI.ServiceMock

# Configure HTTP client to use mock in tests
config :wanderer_notifier, http_client: WandererNotifier.HTTPMock

# Configure the notification service
config :wanderer_notifier, :notifications, service: WandererNotifier.Notifiers.TestNotifier

# Configure the kill determiner
config :wanderer_notifier, :kill_determiner,
  service: WandererNotifier.Notifications.Determiner.KillMock

# Configure Mox
config :mox, :global, true

# Configure the env provider for testing - use real provider to avoid mocking issues
config :wanderer_notifier,
  env_provider: WandererNotifier.Shared.Config.SystemEnvProvider
