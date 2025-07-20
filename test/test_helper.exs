# credo:disable-for-this-file Credo.Check.Consistency.UnusedVariableNames
# Configure test environment before anything else
Application.put_env(:wanderer_notifier, :environment, :test)

# Start ExUnit
ExUnit.start()

# Configure Mox
Application.ensure_all_started(:mox)

# Set up Mox mocks
# Cache behaviour removed in simplification - MockCache no longer needed
# Mox.defmock(WandererNotifier.MockCache, for: WandererNotifier.Infrastructure.Cache.CacheBehaviour)
Mox.defmock(WandererNotifier.MockSystem, for: WandererNotifier.Map.TrackingBehaviour)
Mox.defmock(WandererNotifier.MockCharacter, for: WandererNotifier.Map.TrackingBehaviour)

Mox.defmock(WandererNotifier.MockDeduplication,
  for: WandererNotifier.Domains.Notifications.Deduplication.DeduplicationBehaviour
)

Mox.defmock(WandererNotifier.MockConfig, for: WandererNotifier.Shared.Config.ConfigBehaviour)

Mox.defmock(WandererNotifier.HTTPMock, for: WandererNotifier.Infrastructure.Http.HttpBehaviour)

Mox.defmock(DiscordNotifierMock,
  for: WandererNotifier.Domains.Notifications.Notifiers.Discord.DiscordBehaviour
)

Mox.defmock(WandererNotifier.Infrastructure.Adapters.ESI.ServiceMock,
  for: WandererNotifier.Infrastructure.Adapters.ESI.ServiceBehaviour
)

Mox.defmock(WandererNotifier.Infrastructure.Adapters.ESI.ClientMock,
  for: WandererNotifier.Infrastructure.Adapters.ESI.ClientBehaviour
)

Mox.defmock(WandererNotifier.Domains.Notifications.KillmailNotificationMock,
  for: WandererNotifier.Domains.Notifications.KillmailNotificationBehaviour
)

# Configure application to use mocks
# Cache module removed - using simplified Cache directly
# Application.put_env(:wanderer_notifier, :cache_module, WandererNotifier.MockCache)
Application.put_env(:wanderer_notifier, :system_module, WandererNotifier.MockSystem)
Application.put_env(:wanderer_notifier, :character_module, WandererNotifier.MockCharacter)
Application.put_env(:wanderer_notifier, :deduplication_module, WandererNotifier.MockDeduplication)
Application.put_env(:wanderer_notifier, :config_module, WandererNotifier.MockConfig)

Application.put_env(
  :wanderer_notifier,
  :esi_service,
  WandererNotifier.Infrastructure.Adapters.ESI.ServiceMock
)

Application.put_env(
  :wanderer_notifier,
  :esi_client,
  WandererNotifier.Infrastructure.Adapters.ESI.ClientMock
)

Application.put_env(:wanderer_notifier, :http_client, WandererNotifier.HTTPMock)

# Cache mock stubs removed - using real Cachex in tests
# The simplified cache system uses Cachex directly

# Set up default stubs for deduplication mock
Mox.stub(WandererNotifier.MockDeduplication, :check, fn _, _ -> {:ok, :new} end)
Mox.stub(WandererNotifier.MockDeduplication, :clear_key, fn _, _ -> :ok end)

# Set up default stubs for config mock
Mox.stub(WandererNotifier.MockConfig, :notifications_enabled?, fn -> true end)
Mox.stub(WandererNotifier.MockConfig, :kill_notifications_enabled?, fn -> true end)
Mox.stub(WandererNotifier.MockConfig, :system_notifications_enabled?, fn -> true end)
Mox.stub(WandererNotifier.MockConfig, :character_notifications_enabled?, fn -> true end)

Mox.stub(WandererNotifier.MockConfig, :get_notification_setting, fn _type, _key -> {:ok, true} end)

# Traditional stub for backward compatibility
Mox.stub(WandererNotifier.MockConfig, :get_config, fn ->
  %{
    notifications_enabled: true,
    kill_notifications_enabled: true,
    system_notifications_enabled: true,
    character_notifications_enabled: true
  }
end)

Mox.stub(WandererNotifier.MockConfig, :deduplication_module, fn ->
  WandererNotifier.MockDeduplication
end)

Mox.stub(WandererNotifier.MockConfig, :system_track_module, fn -> WandererNotifier.MockSystem end)

Mox.stub(WandererNotifier.MockConfig, :character_track_module, fn ->
  WandererNotifier.MockCharacter
end)

Mox.stub(WandererNotifier.MockConfig, :notification_determiner_module, fn ->
  WandererNotifier.Domains.Notifications.Determiner.Kill
end)

Mox.stub(WandererNotifier.MockConfig, :killmail_enrichment_module, fn ->
  WandererNotifier.Domains.Killmail.Enrichment
end)

Mox.stub(WandererNotifier.MockConfig, :killmail_notification_module, fn ->
  WandererNotifier.Domains.Notifications.KillmailNotification
end)

# Set up default stubs for system mock
Mox.stub(WandererNotifier.MockSystem, :is_tracked?, fn _id -> {:ok, false} end)

# Set up default stubs for character mock
Mox.stub(WandererNotifier.MockCharacter, :is_tracked?, fn _id -> {:ok, false} end)

# Set up default stubs for HTTP client mock
Mox.stub(WandererNotifier.HTTPMock, :get, fn _url, _headers, _opts ->
  {:ok, %{status_code: 200, body: "{}"}}
end)

Mox.stub(WandererNotifier.HTTPMock, :post, fn _url, _body, _headers, _opts ->
  {:ok, %{status_code: 200, body: "{}"}}
end)

Mox.stub(WandererNotifier.HTTPMock, :post_json, fn _url, _body, _headers, _opts ->
  {:ok, %{status_code: 200, body: "{}"}}
end)

Mox.stub(WandererNotifier.HTTPMock, :request, fn _method, _url, _headers, _body, _opts ->
  {:ok, %{status_code: 200, body: "{}"}}
end)

Mox.stub(WandererNotifier.HTTPMock, :get_killmail, fn _id, _hash ->
  {:ok, %{status_code: 200, body: "{}"}}
end)

# Set up default stubs for ESI service mock
Mox.stub(WandererNotifier.Infrastructure.Adapters.ESI.ServiceMock, :get_killmail, fn _id, _hash ->
  {:ok, %{}}
end)

Mox.stub(WandererNotifier.Infrastructure.Adapters.ESI.ServiceMock, :get_character, fn _id ->
  {:ok, %{}}
end)

Mox.stub(
  WandererNotifier.Infrastructure.Adapters.ESI.ServiceMock,
  :get_corporation_info,
  fn _id -> {:ok, %{}} end
)

Mox.stub(WandererNotifier.Infrastructure.Adapters.ESI.ServiceMock, :get_alliance_info, fn _id ->
  {:ok, %{}}
end)

Mox.stub(WandererNotifier.Infrastructure.Adapters.ESI.ServiceMock, :get_universe_type, fn _id,
                                                                                          _opts ->
  {:ok, %{}}
end)

Mox.stub(WandererNotifier.Infrastructure.Adapters.ESI.ServiceMock, :get_system, fn id, _opts ->
  {:ok, %{"name" => "System-#{id}", "security_status" => 0.5}}
end)

Mox.stub(WandererNotifier.Infrastructure.Adapters.ESI.ServiceMock, :get_type_info, fn _id ->
  {:ok, %{}}
end)

Mox.stub(WandererNotifier.Infrastructure.Adapters.ESI.ServiceMock, :get_system_kills, fn _id,
                                                                                         _limit,
                                                                                         _opts ->
  {:ok, []}
end)

Mox.stub(WandererNotifier.Infrastructure.Adapters.ESI.ServiceMock, :search, fn _query,
                                                                               _categories,
                                                                               _opts ->
  {:ok, %{}}
end)

# Configure logger level for tests
Logger.configure(level: :debug)

# Initialize ETS tables
table_opts = [
  :named_table,
  :public,
  :set,
  {:write_concurrency, true},
  {:read_concurrency, true}
]

# Create tables if they don't exist
if :ets.whereis(:cache_table) == :undefined do
  :ets.new(:cache_table, table_opts)
end

if :ets.whereis(:locks_table) == :undefined do
  :ets.new(:locks_table, table_opts)
end

# Ensure the killmail cache module is always the test mock
Application.put_env(
  :wanderer_notifier,
  :killmail_cache_module,
  WandererNotifier.Test.Support.Mocks
)

# Disable all external services and background processes in test
Application.put_env(:wanderer_notifier, :discord_enabled, false)
Application.put_env(:wanderer_notifier, :scheduler_enabled, false)
Application.put_env(:wanderer_notifier, :character_tracking_enabled, false)
Application.put_env(:wanderer_notifier, :system_notifications_enabled, false)
Application.put_env(:wanderer_notifier, :schedulers_enabled, false)
Application.put_env(:wanderer_notifier, :scheduler_supervisor_enabled, false)
Application.put_env(:wanderer_notifier, :pipeline_worker_enabled, false)

# Disable RedisQ client in tests to prevent HTTP calls
Application.put_env(:wanderer_notifier, :redisq, %{enabled: false})

# Configure cache implementation
Application.put_env(:wanderer_notifier, :cache_name, :wanderer_test_cache)

# Load shared test mocks
Code.require_file("support/test_mocks.ex", __DIR__)
Code.require_file("support/global_mock_config.ex", __DIR__)

# Set up test environment variables
System.put_env("MAP_URL", "http://test.map.url")
System.put_env("MAP_NAME", "test_map")
System.put_env("MAP_API_KEY", "test_map_api_key")
System.put_env("NOTIFIER_API_TOKEN", "test_notifier_token")
System.put_env("LICENSE_KEY", "test_license_key")
System.put_env("LICENSE_MANAGER_API_URL", "http://test.license.url")
System.put_env("DISCORD_WEBHOOK_URL", "http://test.discord.url")
