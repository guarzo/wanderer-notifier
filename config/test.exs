import Config

config :wanderer_notifier,
  # Use test-specific configuration
  http_client: WandererNotifier.MockHTTP,
  discord_client: WandererNotifier.MockDiscord,
  websocket_client: WandererNotifier.MockWebSocket,
  cache_name: :test_cache,

  # Faster timeouts for tests
  api_timeout: 100,

  # Test-specific feature flags
  features: %{
    "send_discord_notifications" => true,
    "track_character_changes" => true,
    # Disable for tests
    "generate_tps_charts" => false
  }

# Prevent Nostrum from starting during tests
config :nostrum,
  token: "fake_token_for_testing",
  gateway_intents: []

# Prevent application from starting external connections
config :wanderer_notifier, :start_external_connections, false

# Configure logger for test environment
config :logger, level: :warning
