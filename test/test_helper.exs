# credo:disable-for-this-file Credo.Check.Consistency.UnusedVariableNames
# Configure test environment before anything else
Application.put_env(:wanderer_notifier, :environment, :test)

# Start ExUnit
ExUnit.start()

# Configure Mox
Application.ensure_all_started(:mox)

# Load test mock infrastructure (with guards to prevent redefinition)
unless Code.ensure_loaded?(WandererNotifier.Test.Support.Mocks.TestMocks) do
  Code.require_file("support/mocks/test_mocks.ex", __DIR__)
end

unless Code.ensure_loaded?(WandererNotifier.Test.Support.Mocks.TestDataFactory) do
  Code.require_file("support/mocks/test_data_factory.ex", __DIR__)
end

# Import test mocks module
alias WandererNotifier.Test.Support.Mocks.TestMocks

# Configure application to use mocks
# Cache module removed - using simplified Cache directly
# Application.put_env(:wanderer_notifier, :cache_module, WandererNotifier.MockCache)
Application.put_env(:wanderer_notifier, :system_module, WandererNotifier.MockSystem)
Application.put_env(:wanderer_notifier, :character_module, WandererNotifier.MockCharacter)
Application.put_env(:wanderer_notifier, :system_track_module, WandererNotifier.MockSystem)
Application.put_env(:wanderer_notifier, :character_track_module, WandererNotifier.MockCharacter)
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

Application.put_env(
  :wanderer_notifier,
  :static_info_module,
  WandererNotifier.Domains.Tracking.StaticInfoMock
)

# Set up all mocks with default behaviors using test infrastructure
TestMocks.setup_all_mocks()

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
Application.put_env(:wanderer_notifier, :cache_name, :wanderer_cache_test)

# Initialize RateLimiter ETS table for tests
unless :ets.whereis(WandererNotifier.RateLimiter) == :undefined do
  :ets.delete(WandererNotifier.RateLimiter)
end

:ets.new(WandererNotifier.RateLimiter, [:set, :public, :named_table])

# Note: Shared test mocks are currently disabled in favor of per-test mocking
# These were commented out during test refactoring to avoid conflicts with Mox setup

# Set up test environment variables
System.put_env("MAP_URL", "http://test.map.url")
System.put_env("MAP_NAME", "test_map")
System.put_env("MAP_API_KEY", "test_map_api_key")
System.put_env("NOTIFIER_API_TOKEN", "test_notifier_token")
System.put_env("LICENSE_KEY", "test_license_key")
System.put_env("LICENSE_MANAGER_API_URL", "http://test.license.url")
System.put_env("DISCORD_WEBHOOK_URL", "http://test.discord.url")
