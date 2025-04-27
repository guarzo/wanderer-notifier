import Config

# Environment-specific configuration
config :wanderer_notifier, :test_env, true
config :wanderer_notifier, :env, :test
config :wanderer_notifier, :disable_status_messages, true

# Test mode configuration
config :nostrum, token: "test_discord_token"

# WandererNotifier test configuration
config :wanderer_notifier,
  discord_bot_token: "test_token",
  discord_channel_id: "123456789",
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
  cache_repository: WandererNotifier.Data.Cache.RepositoryMock,
  zkill_service: WandererNotifier.Api.ZKill.ServiceMock,
  esi_service: WandererNotifier.ESI.ServiceMock

# Configure cache
config :wanderer_notifier, :cache_dir, "test/cache"

# Logger configuration for tests
config :logger, level: :warning
config :logger, :console, format: "[$level] $message\n"
