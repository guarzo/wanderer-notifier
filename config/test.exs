import Config

# Configure the application for testing
config :wanderer_notifier,
  discord_channel_id: "test_channel_id",
  discord_bot_token: "test_bot_token",
  license_key: "test_license_key",
  license_manager_api_url: "https://test.license.manager",
  bot_registration_token: "test_bot_token"

# Use the test notifier for Discord
config :wanderer_notifier, :discord_notifier, WandererNotifier.Discord.TestNotifier

# Configure the HTTP client to use a mock
config :wanderer_notifier, :http_client, WandererNotifier.Http.ClientMock

# Configure logger for testing
config :logger,
  level: :info,
  backends: [:console]

# Reduce log noise during tests
config :logger, :console,
  format: "[$level] $message\n"
