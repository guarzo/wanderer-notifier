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

# Configure Mox
Application.ensure_all_started(:mox)

# Define single mock for repository
Mox.defmock(WandererNotifier.Data.Cache.RepositoryMock,
  for: WandererNotifier.Data.Cache.RepositoryBehaviour
)

# Configure cache implementation
Application.put_env(:wanderer_notifier, :cache_impl, WandererNotifier.ETSCache)

Application.put_env(
  :wanderer_notifier,
  :cache_repository,
  WandererNotifier.Data.Cache.RepositoryMock
)

# Start ExUnit with global mode disabled
ExUnit.start(capture_log: true)

# Initialize ETS tables under supervision
defmodule WandererNotifier.TestSupervisor do
  use Supervisor

  def start_link(init_arg) do
    Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    # Initialize ETS tables under supervision
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

    # Return empty children list since tables are created
    Supervisor.init([], strategy: :one_for_one)
  end
end

# Start the test supervisor
{:ok, _pid} = WandererNotifier.TestSupervisor.start_link([])

# Define mocks for external services
Mox.defmock(WandererNotifier.Api.ZKill.ServiceMock,
  for: WandererNotifier.Api.ZKill.ServiceBehaviour
)

Mox.defmock(WandererNotifier.Api.ESI.ServiceMock, for: WandererNotifier.Api.ESI.ServiceBehaviour)

# Configure application to use mocks
Application.put_env(:wanderer_notifier, :zkill_service, WandererNotifier.Api.ZKill.ServiceMock)
Application.put_env(:wanderer_notifier, :esi_service, WandererNotifier.Api.ESI.ServiceMock)

# Cache-related mocks
Mox.defmock(WandererNotifier.MockCache, for: WandererNotifier.Data.Cache.CacheBehaviour)

# Define mocks for external dependencies
Mox.defmock(WandererNotifier.MockKillmailChartAdapter,
  for: WandererNotifier.ChartService.KillmailChartAdapterBehaviour
)

# Set up application environment for testing
Application.put_env(:wanderer_notifier, :zkill_client, WandererNotifier.Api.ZKill.Client)
Application.put_env(:wanderer_notifier, :esi_service, WandererNotifier.Api.ESI.Service)
Application.put_env(:wanderer_notifier, :cache_helpers, WandererNotifier.MockCacheHelpers)
Application.put_env(:wanderer_notifier, :repository, WandererNotifier.MockRepository)
Application.put_env(:wanderer_notifier, :logger, WandererNotifier.MockLogger)

Application.put_env(
  :wanderer_notifier,
  :killmail_chart_adapter,
  WandererNotifier.MockKillmailChartAdapter
)

# Define mocks for external dependencies
Mox.defmock(WandererNotifier.MockZKillClient, for: WandererNotifier.Api.ZKill.ClientBehaviour)
Mox.defmock(WandererNotifier.MockESI, for: WandererNotifier.Api.ESI.ServiceBehaviour)
Mox.defmock(WandererNotifier.MockLogger, for: WandererNotifier.Logger.Behaviour)
Mox.defmock(WandererNotifier.MockHTTP, for: WandererNotifier.Api.Http.Behaviour)
Mox.defmock(WandererNotifier.MockWebSocket, for: WandererNotifier.Api.ZKill.WebSocketBehaviour)

# Mock Nostrum's API
defmodule Nostrum.Api do
  def start_link, do: {:ok, self()}
  def create_message(_channel_id, _content), do: {:ok, %{}}
  def create_message(_channel_id, _content, _opts), do: {:ok, %{}}
end

# Define mocks for notifiers
Mox.defmock(WandererNotifier.MockStructuredFormatter,
  for: WandererNotifier.Notifiers.StructuredFormatterBehaviour
)

Mox.defmock(WandererNotifier.MockDiscordNotifier,
  for: WandererNotifier.Notifiers.DiscordNotifierBehaviour
)

# Configure application to use mocks
Application.put_env(:wanderer_notifier, :discord_notifier, WandererNotifier.MockDiscordNotifier)

# Set up default stubs for Discord notifier
Mox.stub_with(WandererNotifier.MockDiscordNotifier, WandererNotifier.Test.Stubs.DiscordNotifier)

# Define mocks for cache helpers
Mox.defmock(WandererNotifier.MockCacheHelpers, for: WandererNotifier.Data.Cache.HelpersBehaviour)

Mox.defmock(WandererNotifier.MockRepository, for: WandererNotifier.Data.Cache.RepositoryBehaviour)

Mox.defmock(WandererNotifier.MockKillmailPersistence,
  for: WandererNotifier.Resources.KillmailPersistenceBehaviour
)

# Create a mock for the new Persistence module
Mox.defmock(WandererNotifier.Processing.Killmail.MockPersistence,
  for: WandererNotifier.Processing.Killmail.PersistenceBehaviour
)

# Set Mox to verify on exit
Application.put_env(:mox, :verify_on_exit, true)

# Define mocks for config and date
Mox.defmock(WandererNotifier.MockConfig, for: WandererNotifier.Config.Behaviour)
Mox.defmock(WandererNotifier.MockDate, for: WandererNotifier.DateBehaviour)

# Define mocks for notifier factory
Mox.defmock(WandererNotifier.MockNotifierFactory,
  for: WandererNotifier.Notifiers.FactoryBehaviour
)

# Define mock for Resources.Api
Mox.defmock(WandererNotifier.Resources.MockApi, for: WandererNotifier.Resources.ApiBehaviour)

# Set up application environment for testing
Application.put_env(:wanderer_notifier, :config_module, WandererNotifier.MockConfig)
Application.put_env(:wanderer_notifier, :cache_helpers_module, WandererNotifier.MockCacheHelpers)
Application.put_env(:wanderer_notifier, :notifier_factory, WandererNotifier.MockNotifierFactory)
Application.put_env(:wanderer_notifier, :date_module, WandererNotifier.MockDate)
Application.put_env(:wanderer_notifier, :resources_api, WandererNotifier.Resources.MockApi)

# Load DataCase module
Code.require_file("support/data_case.ex", __DIR__)
