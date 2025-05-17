# Configure test environment before anything else
Application.put_env(:wanderer_notifier, :environment, :test)
Application.put_env(:wanderer_notifier, :schedulers_enabled, false)
Application.put_env(:wanderer_notifier, :scheduler_supervisor_enabled, false)

# Load behaviors first
Code.require_file("support/test_behaviours.ex", __DIR__)

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

# Configure Mox
Application.ensure_all_started(:mox)

# Configure cache implementation
Application.put_env(:wanderer_notifier, :cache_impl, WandererNotifier.ETSCache)

# Start ExUnit with global mode disabled
ExUnit.start(capture_log: true)

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

# Define mocks for external dependencies
# First, redefine the behavior to include the get/1 function
defmodule WandererNotifier.HttpClient.TestBehaviour do
  @moduledoc """
  Modified behavior for HTTP clients in tests
  """
  @callback get(url :: String.t()) :: {:ok, map()} | {:error, term()}
  @callback get(url :: String.t(), headers :: list()) :: {:ok, map()} | {:error, term()}
  @callback get(url :: String.t(), headers :: list(), options :: keyword()) ::
              {:ok, map()} | {:error, term()}
  @callback post(url :: String.t(), body :: any(), headers :: list()) ::
              {:ok, map()} | {:error, term()}
  @callback post_json(url :: String.t(), body :: any(), headers :: list(), options :: keyword()) ::
              {:ok, map()} | {:error, term()}
  @callback request(
              method :: atom(),
              url :: String.t(),
              headers :: list(),
              body :: any(),
              options :: keyword()
            ) :: {:ok, map()} | {:error, term()}
  @callback handle_response(response :: term()) :: {:ok, map()} | {:error, term()}
end

# Define all mocks
Mox.defmock(WandererNotifier.MockHTTP, for: WandererNotifier.HTTP)
Mox.defmock(WandererNotifier.ESI.ServiceMock, for: WandererNotifier.ESI.ServiceBehaviour)

Mox.defmock(WandererNotifier.Killmail.ZKillClientMock,
  for: WandererNotifier.Killmail.ZKillClientBehaviour
)

Mox.defmock(WandererNotifier.Notifications.DiscordNotifierMock,
  for: WandererNotifier.Notifiers.Discord.Behaviour
)

Mox.defmock(WandererNotifier.Api.ESI.ClientMock,
  for: WandererNotifier.TestHelpers.Mocks.ESIBehavior
)

Mox.defmock(WandererNotifier.MockNotifierFactory,
  for: WandererNotifier.Notifications.DispatcherBehaviour
)

Mox.defmock(WandererNotifier.HttpClient.HttpoisonMock, for: WandererNotifier.HttpClient.Behaviour)
Mox.defmock(WandererNotifier.ESI.ClientMock, for: WandererNotifier.ESI.ClientBehaviour)
Mox.defmock(WandererNotifier.Map.MapSystemMock, for: WandererNotifier.Test.SystemBehaviour)
Mox.defmock(WandererNotifier.Map.MapCharacterMock, for: WandererNotifier.Test.CharacterBehaviour)
Mox.defmock(WandererNotifier.MockConfig, for: WandererNotifier.Config.Behaviour)

Mox.defmock(WandererNotifier.MockNotificationsConfig,
  for: WandererNotifier.Test.ConfigBehaviour
)

Mox.defmock(WandererNotifier.Notifications.MockDeduplication,
  for: WandererNotifier.Notifications.Deduplication.Behaviour
)

Mox.defmock(WandererNotifier.Notifications.MockConfig,
  for: WandererNotifier.Test.ConfigBehaviour
)

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

Application.put_env(:wanderer_notifier, :config_module, WandererNotifier.MockConfig)

Application.put_env(
  :wanderer_notifier,
  :notifications_config_module,
  WandererNotifier.MockNotificationsConfig
)

Application.put_env(
  :wanderer_notifier,
  :deduplication_module,
  WandererNotifier.Notifications.MockDeduplication
)

# Set up default stubs for config mocks
Mox.stub(WandererNotifier.MockConfig, :notifications_enabled?, fn -> true end)
Mox.stub(WandererNotifier.MockConfig, :kill_notifications_enabled?, fn -> true end)
Mox.stub(WandererNotifier.MockConfig, :system_notifications_enabled?, fn -> true end)
Mox.stub(WandererNotifier.MockConfig, :character_notifications_enabled?, fn -> true end)

Mox.stub(WandererNotifier.MockConfig, :get_config, fn ->
  %{
    notifications_enabled: true,
    kill_notifications_enabled: true,
    system_notifications_enabled: true,
    character_notifications_enabled: true
  }
end)

Mox.stub(WandererNotifier.MockNotificationsConfig, :get_notification_setting, fn _, _ -> true end)
Mox.stub(WandererNotifier.MockNotificationsConfig, :get_config, fn -> %{} end)

# Set up default stubs for notifications config mock
Mox.stub(WandererNotifier.Notifications.MockConfig, :get_notification_setting, fn _, _ -> true end)

Mox.stub(WandererNotifier.Notifications.MockConfig, :get_config, fn ->
  %{
    notifications_enabled: true,
    kill_notifications_enabled: true,
    system_notifications_enabled: true,
    character_notifications_enabled: true
  }
end)

# Set up default stubs for deduplication mock
Mox.stub(WandererNotifier.Notifications.MockDeduplication, :check, fn _, _ -> {:ok, :new} end)

# Set up default stubs for random killmail requests
Mox.stub(WandererNotifier.Api.ESI.ClientMock, :get_killmail, fn _, _, _ ->
  {:ok,
   %{
     "victim" => %{
       "character_id" => 123,
       "corporation_id" => 456,
       "ship_type_id" => 789
     },
     "solar_system_id" => 30_000_142,
     "attackers" => []
   }}
end)

Mox.stub(WandererNotifier.Api.ESI.ClientMock, :get_character_info, fn _, _ ->
  {:ok, %{"name" => "Test Character"}}
end)

Mox.stub(WandererNotifier.Api.ESI.ClientMock, :get_corporation_info, fn _, _ ->
  {:ok, %{"name" => "Test Corporation", "ticker" => "TEST"}}
end)

Mox.stub(WandererNotifier.Api.ESI.ClientMock, :get_universe_type, fn _, _ ->
  {:ok, %{"name" => "Test Ship"}}
end)

Mox.stub(WandererNotifier.Api.ESI.ClientMock, :get_system, fn _, _ ->
  {:ok, %{"name" => "Test System"}}
end)

# Set Mox to verify on exit
Application.put_env(:mox, :verify_on_exit, true)

# Configure logger level for tests
Logger.configure(level: :warning)

# Start Stats service for tests if needed
if :ets.whereis(:stats_table) == :undefined do
  :ets.new(:stats_table, [:named_table, :public, :set])
end

# Initialize test state for Stats
case GenServer.start_link(WandererNotifier.Core.Stats, [], name: WandererNotifier.Core.Stats) do
  {:ok, pid} -> {:ok, pid}
  {:error, {:already_started, pid}} -> {:ok, pid}
  error -> error
end

# Start and initialize license service with mock state for tests
mock_license_response = %{
  valid: true,
  bot_assigned: true,
  details: %{"license_valid" => true, "valid" => true},
  error: nil,
  error_message: nil,
  last_validated: DateTime.utc_now() |> DateTime.to_string(),
  notification_counts: %{system: 0, character: 0, killmail: 0}
}

case GenServer.start_link(WandererNotifier.License.Service, mock_license_response,
       name: WandererNotifier.License.Service
     ) do
  {:ok, pid} -> {:ok, pid}
  {:error, {:already_started, pid}} -> {:ok, pid}
  error -> error
end

# Helper functions for tests
defmodule WandererNotifier.TestHelpers do
  @moduledoc """
  Helper functions for tests.
  """

  def mock_http_response(status_code, body) do
    {:ok, %{status_code: status_code, body: body}}
  end

  def mock_http_error(reason) do
    {:error, reason}
  end

  def mock_cache_response(value) do
    {:ok, value}
  end

  def mock_cache_error(reason) do
    {:error, reason}
  end

  def mock_notifier_response do
    :ok
  end

  def mock_notifier_error(reason) do
    {:error, reason}
  end
end

# Set up test environment variables
System.put_env("MAP_URL", "http://test.map.url")
System.put_env("MAP_TOKEN", "test_map_token")
System.put_env("MAP_NAME", "test_map")
System.put_env("NOTIFIER_API_TOKEN", "test_notifier_token")
System.put_env("LICENSE_KEY", "test_license_key")
System.put_env("LICENSE_MANAGER_API_URL", "http://test.license.url")
System.put_env("DISCORD_WEBHOOK_URL", "http://test.discord.url")
