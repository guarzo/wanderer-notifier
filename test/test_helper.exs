# Configure test environment before anything else
Application.put_env(:wanderer_notifier, :environment, :test)
Application.put_env(:wanderer_notifier, :schedulers_enabled, false)
Application.put_env(:wanderer_notifier, :scheduler_supervisor_enabled, false)

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
Mox.defmock(WandererNotifier.MockHTTP, for: WandererNotifier.HttpClient.Behaviour)
Mox.defmock(WandererNotifier.ESI.ServiceMock, for: WandererNotifier.ESI.ServiceBehaviour)

Mox.defmock(WandererNotifier.Killmail.ZKillClientMock,
  for: WandererNotifier.Killmail.ZKillClientBehaviour
)

Mox.defmock(WandererNotifier.Notifications.Determiner.KillMock,
  for: WandererNotifier.Notifications.Determiner.KillBehaviour
)

# Define DiscordNotifier mock
Mox.defmock(WandererNotifier.Notifications.DiscordNotifierMock,
  for: WandererNotifier.Notifications.DiscordNotifierBehaviour
)

# Configure application to use mocks
Application.put_env(:wanderer_notifier, :esi_service, WandererNotifier.ESI.ServiceMock)
Application.put_env(:wanderer_notifier, :zkill_client, WandererNotifier.Killmail.ZKillClientMock)

Application.put_env(
  :wanderer_notifier,
  :discord_notifier,
  WandererNotifier.Notifications.DiscordNotifierMock
)

# Set Mox to verify on exit
Application.put_env(:mox, :verify_on_exit, true)

# Set up application environment for testing
Application.put_env(:wanderer_notifier, :config_module, WandererNotifier.MockConfig)
Application.put_env(:wanderer_notifier, :cache_helpers_module, WandererNotifier.MockCacheHelpers)
Application.put_env(:wanderer_notifier, :date_module, WandererNotifier.MockDate)

# Set up test configuration
Application.put_env(:wanderer_notifier, :http_client, WandererNotifier.MockHTTP)
Application.put_env(:wanderer_notifier, :cache_client, WandererNotifier.MockCache)
Application.put_env(:wanderer_notifier, :notifier_client, WandererNotifier.MockNotifier)

# Set up test environment variables
System.put_env("MAP_URL", "http://test.map.url")
System.put_env("MAP_TOKEN", "test_map_token")
System.put_env("MAP_NAME", "test_map")
System.put_env("NOTIFIER_API_TOKEN", "test_notifier_token")
System.put_env("LICENSE_KEY", "test_license_key")
System.put_env("LICENSE_MANAGER_API_URL", "http://test.license.url")
System.put_env("DISCORD_WEBHOOK_URL", "http://test.discord.url")

# Configure logger level for tests
Logger.configure(level: :warning)

# Initialize metric registry for tests
{:ok, _} = WandererNotifier.Killmail.MetricRegistry.initialize()

# Start the metrics agent for tests if not already started
case Agent.start_link(fn -> %{counters: %{}} end, name: :killmail_metrics_agent) do
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

Mox.defmock(WandererNotifier.MockNotifierFactory,
  for: WandererNotifier.Notifiers.NotifierFactoryBehaviour
)

Mox.defmock(WandererNotifier.Api.ESI.ClientMock,
  for: WandererNotifier.TestHelpers.Mocks.ESIBehavior
)

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
