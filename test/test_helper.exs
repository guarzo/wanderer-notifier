# Configure test environment before anything else
Application.put_env(:wanderer_notifier, :environment, :test)

# Disable all external services and background processes in test
Application.put_env(:wanderer_notifier, :discord_enabled, false)
Application.put_env(:wanderer_notifier, :scheduler_enabled, false)
Application.put_env(:wanderer_notifier, :character_tracking_enabled, false)
Application.put_env(:wanderer_notifier, :system_notifications_enabled, false)

# Configure Mox
Application.ensure_all_started(:mox)

# Configure cache implementation
Application.put_env(:wanderer_notifier, :cache_impl, WandererNotifier.ETSCache)

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

# Configure application to use mocks
Application.put_env(:wanderer_notifier, :esi_service, WandererNotifier.Api.ESI.ServiceMock)

# Define mocks for external dependencies
Mox.defmock(WandererNotifier.MockHTTP, for: WandererNotifier.HttpClient.Behaviour)

# Configure application to use mocks
Application.put_env(:wanderer_notifier, :discord_notifier, WandererNotifier.MockDiscordNotifier)

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
Logger.configure(level: :warn)

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
