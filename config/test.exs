import Config

config :wanderer_notifier,
  # Environment
  environment: :test,
  start_external_connections: false,

  # Cache configuration
  cache_name: :test_cache,
  cache_repository: WandererNotifier.Data.Cache.RepositoryMock,

  # Mock clients
  http_client: WandererNotifier.MockHTTP,
  discord_client: WandererNotifier.MockDiscord,
  websocket_client: WandererNotifier.MockWebSocket,

  # Service mocks
  zkill_service: WandererNotifier.Api.ZKill.ServiceMock,
  esi_service: WandererNotifier.Api.ESI.ServiceMock,
  cache_helpers: WandererNotifier.MockCacheHelpers,
  repository: WandererNotifier.MockRepository,
  killmail_persistence: WandererNotifier.MockKillmailPersistence,
  logger: WandererNotifier.MockLogger,
  notifier_factory: WandererNotifier.MockNotifierFactory,
  discord_notifier: WandererNotifier.MockDiscordNotifier,
  structured_formatter: WandererNotifier.MockStructuredFormatter,
  killmail_chart_adapter: WandererNotifier.MockKillmailChartAdapter,
  config_module: WandererNotifier.MockConfig,
  date_module: WandererNotifier.MockDate,

  # Test timeouts
  api_timeout: 100,

  # Feature flags
  features: %{
    "send_discord_notifications" => true,
    "track_character_changes" => true,
    "generate_tps_charts" => false
  }

# Prevent Nostrum from starting during tests
config :nostrum,
  token: "fake_token_for_testing",
  gateway_intents: [],
  start_nostrum: false

# Configure logger for test environment
config :logger, level: :warning
