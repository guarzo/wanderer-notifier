# credo:disable-for-this-file Credo.Check.Consistency.UnusedVariableNames
# Configure test environment before anything else
Application.put_env(:wanderer_notifier, :environment, :test)

# Start ExUnit
ExUnit.start()

# Configure Mox
Application.ensure_all_started(:mox)

# Set up Mox mocks
Mox.defmock(WandererNotifier.MockCache, for: WandererNotifier.Cache.Behaviour)
Mox.defmock(WandererNotifier.MockSystem, for: WandererNotifier.Map.SystemBehaviour)
Mox.defmock(WandererNotifier.MockCharacter, for: WandererNotifier.Map.CharacterBehaviour)

Mox.defmock(WandererNotifier.MockDeduplication,
  for: WandererNotifier.Notifications.Deduplication.Behaviour
)

Mox.defmock(WandererNotifier.MockConfig, for: WandererNotifier.Config.ConfigBehaviour)

Mox.defmock(WandererNotifier.MockDispatcher,
  for: WandererNotifier.Notifications.DispatcherBehaviour
)

Mox.defmock(WandererNotifier.HttpClient.HttpoisonMock, for: WandererNotifier.HttpClient.Behaviour)
Mox.defmock(WandererNotifier.ESI.ServiceMock, for: WandererNotifier.ESI.ServiceBehaviour)
Mox.defmock(WandererNotifier.ESI.ClientMock, for: WandererNotifier.ESI.ClientBehaviour)

Mox.defmock(WandererNotifier.MockNotifierFactory,
  for: WandererNotifier.Notifications.DispatcherBehaviour
)

# Configure application to use mocks
Application.put_env(:wanderer_notifier, :cache_module, WandererNotifier.MockCache)
Application.put_env(:wanderer_notifier, :system_module, WandererNotifier.MockSystem)
Application.put_env(:wanderer_notifier, :character_module, WandererNotifier.MockCharacter)
Application.put_env(:wanderer_notifier, :deduplication_module, WandererNotifier.MockDeduplication)
Application.put_env(:wanderer_notifier, :config_module, WandererNotifier.MockConfig)
Application.put_env(:wanderer_notifier, :dispatcher_module, WandererNotifier.MockDispatcher)
Application.put_env(:wanderer_notifier, :esi_service, WandererNotifier.ESI.ServiceMock)
Application.put_env(:wanderer_notifier, :esi_client, WandererNotifier.ESI.ClientMock)
Application.put_env(:wanderer_notifier, :http_client, WandererNotifier.HttpClient.HttpoisonMock)

# Set up default stubs for cache mock
Mox.stub(WandererNotifier.MockCache, :get, fn _key -> {:ok, %{}} end)
Mox.stub(WandererNotifier.MockCache, :mget, fn _keys -> {:ok, %{}} end)
Mox.stub(WandererNotifier.MockCache, :get_kill, fn _id -> {:ok, %{}} end)
Mox.stub(WandererNotifier.MockCache, :set, fn _key, value, _ttl -> {:ok, value} end)
Mox.stub(WandererNotifier.MockCache, :put, fn _key, value -> {:ok, value} end)
Mox.stub(WandererNotifier.MockCache, :delete, fn _key -> :ok end)
Mox.stub(WandererNotifier.MockCache, :clear, fn -> :ok end)

Mox.stub(WandererNotifier.MockCache, :get_and_update, fn _key, update_fun ->
  {current, updated} = update_fun.(nil)
  {:ok, {current, updated}}
end)

Mox.stub(WandererNotifier.MockCache, :get_recent_kills, fn -> [] end)
Mox.stub(WandererNotifier.MockCache, :init_batch_logging, fn -> :ok end)

# Set up default stubs for deduplication mock
Mox.stub(WandererNotifier.MockDeduplication, :check, fn _, _ -> {:ok, :new} end)
Mox.stub(WandererNotifier.MockDeduplication, :clear_key, fn _, _ -> :ok end)

# Set up default stubs for config mock
Mox.stub(WandererNotifier.MockConfig, :notifications_enabled?, fn -> true end)
Mox.stub(WandererNotifier.MockConfig, :kill_notifications_enabled?, fn -> true end)
Mox.stub(WandererNotifier.MockConfig, :system_notifications_enabled?, fn -> true end)
Mox.stub(WandererNotifier.MockConfig, :character_notifications_enabled?, fn -> true end)

Mox.stub(WandererNotifier.MockConfig, :get_notification_setting, fn _type, _key -> {:ok, true} end)

Mox.stub(WandererNotifier.MockConfig, :get_config, fn ->
  {:ok,
   %{
     notifications: %{
       enabled: true,
       kill: %{
         enabled: true,
         system: %{enabled: true},
         character: %{enabled: true},
         min_value: 100_000_000,
         min_isk_per_character: 50_000_000,
         min_isk_per_corporation: 50_000_000,
         min_isk_per_alliance: 50_000_000,
         min_isk_per_ship: 50_000_000,
         min_isk_per_system: 50_000_000
       }
     }
   }}
end)

# Set up default stubs for system mock
Mox.stub(WandererNotifier.MockSystem, :is_tracked?, fn _id -> true end)

# Set up default stubs for character mock
Mox.stub(WandererNotifier.MockCharacter, :is_tracked?, fn _id -> true end)

# Set up default stubs for dispatcher mock
Mox.stub(WandererNotifier.MockDispatcher, :send_message, fn _ -> {:ok, :sent} end)

# Set up default stubs for notifier factory mock
Mox.stub(WandererNotifier.MockNotifierFactory, :send_message, fn _ -> {:ok, :sent} end)

# Set up default stubs for HTTP client mock
Mox.stub(WandererNotifier.HttpClient.HttpoisonMock, :get, fn _url, _headers, _opts ->
  {:ok, %{status_code: 200, body: "{}"}}
end)

# Set up default stubs for ESI service mock
Mox.stub(WandererNotifier.ESI.ServiceMock, :get_killmail, fn _id, _hash -> {:ok, %{}} end)
Mox.stub(WandererNotifier.ESI.ServiceMock, :get_character, fn _id -> {:ok, %{}} end)
Mox.stub(WandererNotifier.ESI.ServiceMock, :get_corporation_info, fn _id -> {:ok, %{}} end)
Mox.stub(WandererNotifier.ESI.ServiceMock, :get_alliance_info, fn _id -> {:ok, %{}} end)
Mox.stub(WandererNotifier.ESI.ServiceMock, :get_universe_type, fn _id, _opts -> {:ok, %{}} end)
Mox.stub(WandererNotifier.ESI.ServiceMock, :get_system, fn _id -> {:ok, %{}} end)
Mox.stub(WandererNotifier.ESI.ServiceMock, :get_type_info, fn _id -> {:ok, %{}} end)

Mox.stub(WandererNotifier.ESI.ServiceMock, :get_system_kills, fn _id, _limit, _opts ->
  {:ok, []}
end)

Mox.stub(WandererNotifier.ESI.ServiceMock, :search, fn _query, _categories, _opts ->
  {:ok, %{}}
end)

# Configure logger level for tests
Logger.configure(level: :warning)

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

# Configure cache implementation
Application.put_env(:wanderer_notifier, :cache_name, :wanderer_test_cache)

# Load shared test mocks
Code.require_file("support/test_mocks.ex", __DIR__)

# Set up test environment variables
System.put_env("MAP_URL", "http://test.map.url")
System.put_env("MAP_TOKEN", "test_map_token")
System.put_env("MAP_NAME", "test_map")
System.put_env("NOTIFIER_API_TOKEN", "test_notifier_token")
System.put_env("LICENSE_KEY", "test_license_key")
System.put_env("LICENSE_MANAGER_API_URL", "http://test.license.url")
System.put_env("DISCORD_WEBHOOK_URL", "http://test.discord.url")
