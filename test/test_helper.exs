# Set up ExUnit
ExUnit.start(exclude: [:integration, :pending, :property, :slow])

# Configure test environment before anything else
Application.put_env(:wanderer_notifier, :environment, :test)

# Prevent Nostrum from starting
Application.put_env(:nostrum, :disabled, true)

# Load environment variables from .env file if it exists
if File.exists?(".env") do
  ".env"
  |> File.read!()
  |> String.split("\n")
  |> Enum.filter(&(String.trim(&1) != ""))
  |> Enum.each(fn line ->
    case String.split(line, "=") do
      [key, value] ->
        System.put_env(String.trim(key), String.trim(value))

      _ ->
        :ok
    end
  end)
end

# Disable all external services and background processes in test
Application.put_env(:wanderer_notifier, :discord_enabled, false)
Application.put_env(:wanderer_notifier, :scheduler_enabled, false)
Application.put_env(:wanderer_notifier, :character_tracking_enabled, false)
Application.put_env(:wanderer_notifier, :system_notifications_enabled, false)
Application.put_env(:wanderer_notifier, :kill_charts_enabled, false)
Application.put_env(:wanderer_notifier, :map_charts_enabled, false)

# Load behaviors before using Mox
Code.require_file("support/behaviors.ex", __DIR__)
Code.require_file("support/mock_adapters.exs", __DIR__)
Code.require_file("support/mock_extensions.ex", __DIR__)
Code.require_file("support/data_case.ex", __DIR__)

# Configure Mox
Application.ensure_all_started(:mox)

# Configure Mox for testing
Application.put_env(:mox, :verify_on_exit, true)

# Configure Ecto to use sandbox adapter for testing
Application.put_env(:wanderer_notifier, WandererNotifier.Repo,
  username: "postgres",
  password: "postgres",
  database: "wanderer_notifier_test",
  hostname: "localhost",
  pool: Ecto.Adapters.SQL.Sandbox,
  log: false
)

# Set up mocks for ESI and ZKill services
Mox.defmock(WandererNotifier.Api.ESI.ServiceMock, for: WandererNotifier.Api.ESI.ServiceBehaviour)

Mox.defmock(WandererNotifier.Api.ZKill.ServiceMock,
  for: WandererNotifier.Api.ZKill.ServiceBehaviour
)

# Set up mocks for caching
Mox.defmock(WandererNotifier.MockCache, for: WandererNotifier.Cache.Behaviour)
Mox.defmock(WandererNotifier.MockCacheHelpers, for: WandererNotifier.Cache.HelpersBehaviour)

# Set up mocks for ZKill client
Mox.defmock(WandererNotifier.MockZKillClient, for: WandererNotifier.Api.ZKill.ClientBehaviour)

# Set up mocks for ESI client
Mox.defmock(WandererNotifier.MockESI, for: WandererNotifier.Api.ESI.Behaviour)

# Set up mocks for Logger
Mox.defmock(WandererNotifier.MockLogger, for: WandererNotifier.Logger.LoggerBehaviour)

# Set up mocks for repository
Mox.defmock(WandererNotifier.MockRepository, for: WandererNotifier.Data.RepositoryBehaviour)

# Set up mocks for config
Mox.defmock(WandererNotifier.MockConfig, for: WandererNotifier.Config.Behaviour)

# Set up mocks for date
Mox.defmock(WandererNotifier.MockDate, for: WandererNotifier.DateBehaviour)

# Set up mocks for notifier factory
Mox.defmock(WandererNotifier.MockNotifierFactory,
  for: WandererNotifier.Notifiers.FactoryBehaviour
)

# Mox support for Discord
defmodule Nostrum.Api do
  def create_message(_, _) do
    {:ok, %{}}
  end
end

defmodule Nostrum.Api.Message do
  def create_embed_message(_, _) do
    {:ok, %{}}
  end
end

# Set up application environment for testing
Application.put_env(:wanderer_notifier, :config_module, WandererNotifier.MockConfig)
Application.put_env(:wanderer_notifier, :cache_helpers_module, WandererNotifier.MockCacheHelpers)
Application.put_env(:wanderer_notifier, :notifier_factory, WandererNotifier.MockNotifierFactory)
Application.put_env(:wanderer_notifier, :date_module, WandererNotifier.MockDate)
Application.put_env(:wanderer_notifier, :resources_api, WandererNotifier.Resources.MockApi)

# Define mocks using Mox
Mox.defmock(WandererNotifier.Killmail.Core.MockValidator,
  for: WandererNotifier.Killmail.Core.ValidatorBehaviour
)

Mox.defmock(WandererNotifier.Killmail.Processing.MockCache,
  for: WandererNotifier.Killmail.Processing.CacheBehaviour
)

Mox.defmock(WandererNotifier.Killmail.Processing.MockEnrichment,
  for: WandererNotifier.Killmail.Processing.EnrichmentBehaviour
)

Mox.defmock(WandererNotifier.Killmail.Processing.MockNotificationDeterminer,
  for: WandererNotifier.Killmail.Processing.NotificationDeterminerBehaviour
)

Mox.defmock(WandererNotifier.Killmail.Processing.MockNotification,
  for: WandererNotifier.Killmail.Processing.NotificationBehaviour
)

Mox.defmock(WandererNotifier.Killmail.Processing.MockPersistence,
  for: WandererNotifier.Killmail.Processing.PersistenceBehaviour
)

# Set up global mocks (these will be used when you need to override impl modules)
Application.put_env(:wanderer_notifier, :validator, WandererNotifier.Killmail.Core.MockValidator)
Application.put_env(:wanderer_notifier, :cache, WandererNotifier.Killmail.Processing.MockCache)

Application.put_env(
  :wanderer_notifier,
  :enrichment,
  WandererNotifier.Killmail.Processing.MockEnrichment
)

Application.put_env(
  :wanderer_notifier,
  :notification_determiner,
  WandererNotifier.Killmail.Processing.MockNotificationDeterminer
)

Application.put_env(
  :wanderer_notifier,
  :notification,
  WandererNotifier.Killmail.Processing.MockNotification
)

Application.put_env(
  :wanderer_notifier,
  :persistence_module,
  WandererNotifier.Killmail.Processing.MockPersistence
)

# Define the mock using Mox
Mox.defmock(WandererNotifier.Killmail.Processing.MockProcessor,
  for: WandererNotifier.Killmail.Processing.ProcessorBehaviour
)

Application.put_env(
  :wanderer_notifier,
  :processor,
  WandererNotifier.Killmail.Processing.MockProcessor
)

# Define a behavior for Features
defmodule WandererNotifier.Config.FeaturesBehaviour do
  @callback persistence_enabled?() :: boolean()
  @callback cache_enabled?() :: boolean()
  @callback notifications_enabled?() :: boolean()
  @callback system_notifications_enabled?() :: boolean()
end

# Define the mock
Mox.defmock(WandererNotifier.Config.MockFeatures, for: WandererNotifier.Config.FeaturesBehaviour)

# Configure the application to use the mock during tests
Application.put_env(:wanderer_notifier, :features, WandererNotifier.Config.MockFeatures)

# Define behaviors for HTTP mocking
defmodule WandererNotifier.HTTP.Behaviour do
  @callback get(url :: String.t(), headers :: list(), options :: keyword()) ::
              {:ok, map() | String.t()} | {:error, any()}
  @callback post(
              url :: String.t(),
              body :: map() | String.t(),
              headers :: list(),
              options :: keyword()
            ) ::
              {:ok, map() | String.t()} | {:error, any()}
  @callback put(
              url :: String.t(),
              body :: map() | String.t(),
              headers :: list(),
              options :: keyword()
            ) ::
              {:ok, map() | String.t()} | {:error, any()}
  @callback delete(url :: String.t(), headers :: list(), options :: keyword()) ::
              {:ok, map() | String.t()} | {:error, any()}
end

# Define HTTP mock module
Mox.defmock(WandererNotifier.MockHTTP, for: WandererNotifier.HTTP.Behaviour)

# Configure the application to use the mock during tests
Application.put_env(:wanderer_notifier, :http_client, WandererNotifier.MockHTTP)

# Apply mock extensions manually in test files instead
# WandererNotifier.MockConfigExtensions.add_expectations()
# WandererNotifier.MockZKillClientExtensions.add_expectations()

# Apply mock extensions by default to fix the failing tests
WandererNotifier.MockConfigExtensions.add_expectations()
WandererNotifier.MockZKillClientExtensions.add_expectations()
WandererNotifier.MockRepositoryExtensions.add_expectations()

# Add stubs for Data.Cache.RepositoryMock
Mox.stub(WandererNotifier.Data.Cache.RepositoryMock, :get, fn _key -> nil end)
Mox.stub(WandererNotifier.Data.Cache.RepositoryMock, :put, fn _key, _value -> :ok end)
Mox.stub(WandererNotifier.Data.Cache.RepositoryMock, :delete, fn _key -> :ok end)
Mox.stub(WandererNotifier.Data.Cache.RepositoryMock, :set, fn _key, _value, _ttl -> :ok end)
Mox.stub(WandererNotifier.Data.Cache.RepositoryMock, :clear, fn -> :ok end)
Mox.stub(WandererNotifier.Data.Cache.RepositoryMock, :exists?, fn _key -> false end)

Mox.stub(WandererNotifier.Data.Cache.RepositoryMock, :get_and_update, fn _key, _fun ->
  {nil, nil}
end)

Mox.stub(WandererNotifier.Data.Cache.RepositoryMock, :get_tracked_characters, fn -> [] end)

# Add stubs for MockStructuredFormatter
Mox.stub(WandererNotifier.MockStructuredFormatter, :format_system_status_message, fn _title,
                                                                                     _msg,
                                                                                     _embed,
                                                                                     _footer,
                                                                                     _fields,
                                                                                     _thumbnail,
                                                                                     _color,
                                                                                     _timestamp ->
  %{embeds: [%{title: "Test"}]}
end)

Mox.stub(WandererNotifier.MockStructuredFormatter, :to_discord_format, fn _notification ->
  %{embeds: [%{title: "Test"}]}
end)

# Add stubs for MockKillmailChartAdapter
Mox.stub(WandererNotifier.MockKillmailChartAdapter, :generate_weekly_kills_chart, fn ->
  {:ok, "http://example.com/chart.png"}
end)

# Setup Mox mocks
Mox.defmock(WandererNotifier.MockConfig, for: WandererNotifier.Config.Behaviour)
Mox.defmock(WandererNotifier.MockCache, for: WandererNotifier.Cache.Behaviour)
Mox.defmock(WandererNotifier.MockCacheHelpers, for: WandererNotifier.Cache.HelpersBehaviour)
Mox.defmock(WandererNotifier.MockESI, for: WandererNotifier.Api.ESI.Behaviour)
Mox.defmock(WandererNotifier.MockZKillClient, for: WandererNotifier.Api.ZKill.ClientBehaviour)

Mox.defmock(WandererNotifier.Api.ZKill.ServiceMock,
  for: WandererNotifier.Api.ZKill.ServiceBehaviour
)

Mox.defmock(WandererNotifier.Api.ESI.ServiceMock, for: WandererNotifier.Api.ESI.ServiceBehaviour)
Mox.defmock(WandererNotifier.MockLogger, for: WandererNotifier.Logger.LoggerBehaviour)
Mox.defmock(WandererNotifier.MockRepository, for: WandererNotifier.Data.RepositoryBehaviour)
Mox.defmock(WandererNotifier.MockDate, for: WandererNotifier.DateBehaviour)

Mox.defmock(WandererNotifier.MockNotifierFactory,
  for: WandererNotifier.Notifiers.FactoryBehaviour
)

Mox.defmock(WandererNotifier.MockStructuredFormatter,
  for: WandererNotifier.Notifiers.StructuredFormatterBehaviour
)

Mox.defmock(WandererNotifier.MockDiscordNotifier,
  for: WandererNotifier.Notifiers.Discord.NotifierBehaviour
)

# Global test fixtures
setup_fixtures = fn path ->
  path
  |> Path.join("**/*.json")
  |> Path.wildcard()
  |> Enum.each(fn file ->
    fixture_name =
      file
      |> Path.basename(".json")
      |> String.to_atom()

    content = File.read!(file)
    :persistent_term.put({:test_fixture, fixture_name}, content)
  end)
end

# Setup fixtures
setup_fixtures.("test/fixtures")

# Mock Nostrum modules used in tests
defmodule Nostrum.Api do
  defmodule Message do
    def create(channel_id, content) when is_binary(content) do
      {:ok, %{channel_id: channel_id, content: content}}
    end

    def create(channel_id, %{content: _} = payload) do
      {:ok, Map.put(payload, :channel_id, channel_id)}
    end
  end

  def create_message(channel_id, content) do
    Message.create(channel_id, content)
  end
end

# Always provide some default test environment variables
System.put_env("WN_DISCORD_WEBHOOK_URL", "https://example.com/webhook")
System.put_env("WN_DISCORD_API_TOKEN", "test_token")
System.put_env("WN_DB_NAME", "test_db")
System.put_env("WN_DB_USER", "test_user")
System.put_env("WN_DB_PASS", "test_pass")
System.put_env("WN_DB_HOST", "localhost")
System.put_env("WN_DB_PORT", "5432")

# Add mock extension functions
Code.require_file("test/support/mock_extensions.ex")
WandererNotifier.MockConfigExtensions.add_expectations()
WandererNotifier.MockZKillClientExtensions.add_expectations()
WandererNotifier.MockRepositoryExtensions.add_expectations()

# Add behaviors
Code.require_file("test/support/behaviors.ex")

# Add mocks for adapter modules
Code.require_file("test/support/mock_adapters.exs")

# For FeaturesBehaviour
defmodule WandererNotifier.Config.FeaturesBehaviour do
  @callback notifications_enabled?() :: boolean()
  @callback system_tracking_enabled?() :: boolean()
  @callback system_notifications_enabled?() :: boolean()
  @callback tracked_systems_notifications_enabled?() :: boolean()
  @callback character_tracking_enabled?() :: boolean()
  @callback character_notifications_enabled?() :: boolean()
  @callback tracked_characters_notifications_enabled?() :: boolean()
  @callback kill_notifications_enabled?() :: boolean()
  @callback kill_charts_enabled?() :: boolean()
  @callback activity_charts_enabled?() :: boolean()
  @callback map_charts_enabled?() :: boolean()
  @callback cache_enabled?() :: boolean()
  @callback get_feature_status() :: map()
end

Mox.defmock(WandererNotifier.MockFeatures, for: WandererNotifier.Config.FeaturesBehaviour)
Mox.stub(WandererNotifier.MockFeatures, :cache_enabled?, fn -> true end)
