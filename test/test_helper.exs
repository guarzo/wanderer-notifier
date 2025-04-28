# Configure test environment before anything else
Application.put_env(:wanderer_notifier, :environment, :test)

# Disable all external services and background processes in test
Application.put_env(:wanderer_notifier, :discord_enabled, false)
Application.put_env(:wanderer_notifier, :scheduler_enabled, false)
Application.put_env(:wanderer_notifier, :character_tracking_enabled, false)
Application.put_env(:wanderer_notifier, :system_notifications_enabled, false)

# Configure Mox
Application.ensure_all_started(:mox)

# Define single mock for repository
Mox.defmock(WandererNotifier.Cache.RepositoryMock,
  for: WandererNotifier.Cache.RepositoryBehaviour
)

# Configure cache implementation
Application.put_env(:wanderer_notifier, :cache_impl, WandererNotifier.ETSCache)

Application.put_env(
  :wanderer_notifier,
  :cache_repository,
  WandererNotifier.Cache.RepositoryMock
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
Mox.defmock(WandererNotifier.Api.ESI.ServiceMock, for: WandererNotifier.Api.ESI.ServiceBehaviour)

# Configure application to use mocks
Application.put_env(:wanderer_notifier, :esi_service, WandererNotifier.Api.ESI.ServiceMock)

# Cache-related mocks
Mox.defmock(WandererNotifier.MockCache, for: WandererNotifier.Cache.CacheBehaviour)

# Define mocks for external dependencies
Mox.defmock(WandererNotifier.MockESI, for: WandererNotifier.Api.ESI.ServiceBehaviour)
Mox.defmock(WandererNotifier.MockLogger, for: WandererNotifier.Logger.Behaviour)
Mox.defmock(WandererNotifier.MockHTTP, for: WandererNotifier.Api.Http.Behaviour)

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
Mox.defmock(WandererNotifier.MockCacheHelpers, for: WandererNotifier.Cache.HelpersBehaviour)

Mox.defmock(WandererNotifier.MockRepository, for: WandererNotifier.Cache.RepositoryBehaviour)

# Set Mox to verify on exit
Application.put_env(:mox, :verify_on_exit, true)

# Define mocks for config and date
Mox.defmock(WandererNotifier.MockConfig, for: WandererNotifier.Config.Behaviour)
Mox.defmock(WandererNotifier.MockDate, for: WandererNotifier.DateBehaviour)

# Define mocks for notifier factory
Mox.defmock(WandererNotifier.MockNotifierFactory,
  for: WandererNotifier.Notifiers.FactoryBehaviour
)

# Set up application environment for testing
Application.put_env(:wanderer_notifier, :config_module, WandererNotifier.MockConfig)
Application.put_env(:wanderer_notifier, :cache_helpers_module, WandererNotifier.MockCacheHelpers)
Application.put_env(:wanderer_notifier, :notifier_factory, WandererNotifier.MockNotifierFactory)
Application.put_env(:wanderer_notifier, :date_module, WandererNotifier.MockDate)
