# credo:disable-for-this-file Credo.Check.Consistency.UnusedVariableNames
# Configure test environment before anything else
Application.put_env(:wanderer_notifier, :environment, :test)
Application.put_env(:wanderer_notifier, :schedulers_enabled, false)
Application.put_env(:wanderer_notifier, :scheduler_supervisor_enabled, false)

# Start ExUnit with global mode disabled
ExUnit.start(capture_log: true)

# Configure Mox
Application.ensure_all_started(:mox)

# Define the DispatcherBehaviour
defmodule WandererNotifier.Notifications.DispatcherBehaviour do
  @callback dispatch(any()) :: :ok | {:error, term()}
  @callback send_message(any()) :: :ok | {:error, term()}
end

# Define the Cache Behaviour
defmodule WandererNotifier.Cache.Behaviour do
  @callback get(String.t()) :: {:ok, any()} | {:error, term()}
  @callback mget([String.t()]) :: {:ok, map()} | {:error, term()}
  @callback get_kill(integer()) :: {:ok, map()} | {:error, term()}
  @callback set(String.t(), any(), integer()) :: {:ok, any()} | {:error, term()}
  @callback put(String.t(), any()) :: {:ok, any()} | {:error, term()}
  @callback delete(String.t()) :: :ok | {:error, term()}
  @callback clear() :: :ok | {:error, term()}
  @callback get_and_update(String.t(), (any() -> {any(), any()})) ::
              {:ok, {any(), any()}} | {:error, term()}
  @callback get_recent_kills() :: [map()]
  @callback init_batch_logging() :: :ok
end

# Define the Config Behaviour
defmodule WandererNotifier.Config.ConfigBehaviour do
  @callback get_config() :: {:ok, map()} | {:error, term()}
  @callback notifications_enabled?() :: boolean()
  @callback kill_notifications_enabled?() :: boolean()
  @callback system_notifications_enabled?() :: boolean()
  @callback character_notifications_enabled?() :: boolean()
  @callback get_notification_setting(atom(), String.t()) :: {:ok, boolean()} | {:error, term()}
end

# Define the Deduplication Behaviour
defmodule WandererNotifier.Notifications.Deduplication.Behaviour do
  @callback check(atom(), integer()) :: {:ok, :new | :duplicate} | {:error, term()}
  @callback clear_key(atom(), integer()) :: :ok | {:error, term()}
end

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

Mox.defmock(WandererNotifier.ESI.ServiceMock, for: WandererNotifier.ESI.ServiceBehaviour)
Mox.defmock(WandererNotifier.ESI.ClientMock, for: WandererNotifier.ESI.ServiceBehaviour)

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
Mox.stub(WandererNotifier.MockDispatcher, :dispatch, fn _ -> :ok end)

# Set up default stubs for notifier factory mock
Mox.stub(WandererNotifier.MockNotifierFactory, :send_message, fn _ -> :ok end)
Mox.stub(WandererNotifier.MockNotifierFactory, :dispatch, fn _ -> :ok end)

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

# Define the ESI ClientBehaviour
defmodule WandererNotifier.ESI.ClientBehaviour do
  @callback get_killmail(String.t(), String.t(), Keyword.t()) :: {:ok, map()} | {:error, term()}
  @callback get_character_info(String.t(), Keyword.t()) :: {:ok, map()} | {:error, term()}
  @callback get_corporation_info(String.t(), Keyword.t()) :: {:ok, map()} | {:error, term()}
  @callback get_universe_type(String.t(), Keyword.t()) :: {:ok, map()} | {:error, term()}
  @callback get_system(String.t(), Keyword.t()) :: {:ok, map()} | {:error, term()}
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
Application.put_env(:wanderer_notifier, :cache_impl, WandererNotifier.ETSCache)

# Load shared test mocks
Code.require_file("support/test_mocks.ex", __DIR__)

# Configure application to use mocks
Application.put_env(:wanderer_notifier, :esi_service, WandererNotifier.ESI.ServiceMock)
Application.put_env(:wanderer_notifier, :zkill_client, WandererNotifier.Killmail.ZKillClientMock)

Application.put_env(
  :wanderer_notifier,
  :http_client_impl,
  WandererNotifier.Test.Support.HttpClientMock
)

Application.put_env(
  :wanderer_notifier,
  :discord_notifier,
  WandererNotifier.Notifications.DiscordNotifierMock
)

# Set up test environment variables
System.put_env("MAP_URL", "http://test.map.url")
System.put_env("MAP_TOKEN", "test_map_token")
System.put_env("MAP_NAME", "test_map")
System.put_env("NOTIFIER_API_TOKEN", "test_notifier_token")
System.put_env("LICENSE_KEY", "test_license_key")
System.put_env("LICENSE_MANAGER_API_URL", "http://test.license.url")
System.put_env("DISCORD_WEBHOOK_URL", "http://test.discord.url")
