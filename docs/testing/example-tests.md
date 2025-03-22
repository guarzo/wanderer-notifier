# WandererNotifier Example Tests

This document provides example test implementations for key components of the WandererNotifier application. These examples demonstrate how to apply the testing strategy to specific parts of the codebase.

## Setup and Infrastructure

### Basic Test Helper

```elixir
# test/test_helper.exs
ExUnit.start()

# Define mocks for external dependencies
Mox.defmock(WandererNotifier.MockHTTP, for: WandererNotifier.HTTP.Behaviour)
Mox.defmock(WandererNotifier.MockCache, for: WandererNotifier.Cache.Behaviour)
Mox.defmock(WandererNotifier.MockDiscord, for: WandererNotifier.Discord.Behaviour)
Mox.defmock(WandererNotifier.MockWebSocket, for: WandererNotifier.WebSocket.Behaviour)

# Set Mox global mode for integration tests where needed
Application.put_env(:mox, :verify_on_exit, true)
```

### HTTP Behaviour Definition

```elixir
# lib/wanderer_notifier/http/behaviour.ex
defmodule WandererNotifier.HTTP.Behaviour do
  @moduledoc """
  Defines the behaviour for HTTP clients to enable mocking in tests.
  """

  @type headers :: [{String.t(), String.t()}]
  @type options :: Keyword.t()
  @type response :: %{status: integer(), body: String.t() | map(), headers: headers()}

  @callback get(url :: String.t(), headers :: headers(), options :: options()) ::
              {:ok, response()} | {:error, term()}

  @callback post(url :: String.t(), body :: term(), headers :: headers(), options :: options()) ::
              {:ok, response()} | {:error, term()}
end
```

### Sample Fixture

```elixir
# test/support/fixtures/api_responses.ex
defmodule WandererNotifier.Test.Fixtures.ApiResponses do
  @moduledoc """
  Provides fixture data for API responses used in tests.
  """

  def map_systems_response do
    %{
      "systems" => [
        %{
          "id" => "J123456",
          "name" => "Test System",
          "security_status" => -1.0,
          "region_id" => 10000001,
          "tracked" => true,
          "activity" => 25
        },
        %{
          "id" => "J654321",
          "name" => "Another System",
          "security_status" => -0.9,
          "region_id" => 10000002,
          "tracked" => false,
          "activity" => 5
        }
      ]
    }
  end

  def esi_character_response do
    %{
      "character_id" => 12345,
      "corporation_id" => 67890,
      "alliance_id" => 54321,
      "name" => "Test Character",
      "security_status" => 5.0
    }
  end

  def zkill_message do
    %{
      "killID" => 12345678,
      "killmail_time" => "2023-06-15T12:34:56Z",
      "solar_system_id" => 30000142,
      "victim" => %{
        "character_id" => 12345,
        "corporation_id" => 67890,
        "ship_type_id" => 582
      },
      "attackers" => [
        %{
          "character_id" => 98765,
          "corporation_id" => 54321,
          "ship_type_id" => 11567
        }
      ],
      "zkb" => %{
        "totalValue" => 100000000.0,
        "points" => 10
      }
    }
  end
end
```

## Unit Test Examples

### Data Structure Tests

```elixir
# test/wanderer_notifier/data/map_system_test.exs
defmodule WandererNotifier.Data.MapSystemTest do
  use ExUnit.Case

  alias WandererNotifier.Data.MapSystem

  describe "new/1" do
    test "creates a valid map system with all fields" do
      params = %{
        id: "J123456",
        name: "Test System",
        security_status: -1.0,
        region_id: 10000001,
        tracked: true,
        activity: 25
      }

      system = MapSystem.new(params)

      assert system.id == "J123456"
      assert system.name == "Test System"
      assert system.security_status == -1.0
      assert system.region_id == 10000001
      assert system.tracked == true
      assert system.activity == 25
    end

    test "sets default values for missing fields" do
      params = %{
        id: "J123456",
        name: "Test System"
      }

      system = MapSystem.new(params)

      assert system.id == "J123456"
      assert system.name == "Test System"
      assert system.security_status == 0.0
      assert system.region_id == nil
      assert system.tracked == false
      assert system.activity == 0
    end

    test "validates system ID format" do
      params = %{
        id: "invalid",
        name: "Invalid System"
      }

      assert_raise ArgumentError, ~r/Invalid system ID format/, fn ->
        MapSystem.new(params)
      end
    end
  end

  describe "wormhole?/1" do
    test "returns true for J-space systems" do
      system = MapSystem.new(%{id: "J123456", name: "WH System"})
      assert MapSystem.wormhole?(system) == true
    end

    test "returns false for non-J-space systems" do
      system = MapSystem.new(%{id: "30000142", name: "K-space System"})
      assert MapSystem.wormhole?(system) == false
    end
  end
end
```

### Helper Function Tests

```elixir
# test/wanderer_notifier/helpers/string_utils_test.exs
defmodule WandererNotifier.Helpers.StringUtilsTest do
  use ExUnit.Case

  alias WandererNotifier.Helpers.StringUtils

  describe "truncate/2" do
    test "truncates strings longer than the limit" do
      assert StringUtils.truncate("This is a very long string", 10) == "This is a..."
    end

    test "does not truncate strings shorter than the limit" do
      assert StringUtils.truncate("Short", 10) == "Short"
    end

    test "handles nil values" do
      assert StringUtils.truncate(nil, 10) == ""
    end
  end

  describe "system_url/1" do
    test "creates URL for J-space system" do
      assert StringUtils.system_url("J123456") == "https://wanderer.app/system/J123456"
    end

    test "creates URL for K-space system" do
      assert StringUtils.system_url("30000142") == "https://wanderer.app/system/30000142"
    end
  end
end
```

## Component Test Examples

### API Client Tests

```elixir
# test/wanderer_notifier/api/map/systems_client_test.exs
defmodule WandererNotifier.Api.Map.SystemsClientTest do
  use ExUnit.Case
  import Mox

  alias WandererNotifier.Api.Map.SystemsClient
  alias WandererNotifier.Test.Fixtures.ApiResponses

  # Ensure mocks are verified after each test
  setup :verify_on_exit!

  # Inject the mock HTTP client for this test
  setup do
    Application.put_env(:wanderer_notifier, :http_client, WandererNotifier.MockHTTP)
    :ok
  end

  describe "get_tracked_systems/0" do
    test "returns parsed systems when API call succeeds" do
      # Arrange - Set up mock expectations
      WandererNotifier.MockHTTP
      |> expect(:get, fn url, _headers, _options ->
        assert String.contains?(url, "/api/systems/tracked")
        {:ok, %{status: 200, body: ApiResponses.map_systems_response()}}
      end)

      # Act - Call the function under test
      result = SystemsClient.get_tracked_systems()

      # Assert - Check the result
      assert {:ok, systems} = result
      assert length(systems) == 2
      assert Enum.at(systems, 0).id == "J123456"
      assert Enum.at(systems, 0).tracked == true
    end

    test "returns error when API call fails" do
      # Arrange - Set up mock expectations for failure
      WandererNotifier.MockHTTP
      |> expect(:get, fn _url, _headers, _options ->
        {:error, %{reason: "connection_failed"}}
      end)

      # Act - Call the function under test
      result = SystemsClient.get_tracked_systems()

      # Assert - Check the error result
      assert {:error, reason} = result
      assert reason == %{reason: "connection_failed"}
    end

    test "returns error when API returns non-200 status" do
      # Arrange - Set up mock expectations for non-200 response
      WandererNotifier.MockHTTP
      |> expect(:get, fn _url, _headers, _options ->
        {:ok, %{status: 404, body: %{"error" => "Not found"}}}
      end)

      # Act - Call the function under test
      result = SystemsClient.get_tracked_systems()

      # Assert - Check the error result
      assert {:error, :not_found} = result
    end
  end
end
```

### Cache Repository Tests

```elixir
# test/wanderer_notifier/cache/repository_test.exs
defmodule WandererNotifier.Cache.RepositoryTest do
  use ExUnit.Case

  alias WandererNotifier.Cache.Repository

  setup do
    # Start a dedicated Cachex instance for testing
    {:ok, pid} = Cachex.start_link(:test_cache)

    # Configure the repository to use the test cache
    Application.put_env(:wanderer_notifier, :cache_name, :test_cache)

    # Return the cache PID so we can stop it after the test
    %{cache_pid: pid}
  end

  describe "put/3 and get/2" do
    test "stores and retrieves values" do
      # Arrange
      key = "test_key"
      value = %{name: "Test Value", id: 123}

      # Act - Store the value
      assert {:ok, true} = Repository.put(key, value)

      # Assert - Retrieve and verify the value
      assert {:ok, retrieved} = Repository.get(key)
      assert retrieved == value
    end

    test "returns nil for non-existent keys" do
      assert {:ok, nil} = Repository.get("non_existent_key")
    end

    test "respects TTL setting" do
      # Arrange
      key = "expiring_key"
      value = "This will expire"
      ttl = 100  # 100ms TTL

      # Act - Store with short TTL
      assert {:ok, true} = Repository.put(key, value, ttl: ttl)

      # Assert - Value exists initially
      assert {:ok, ^value} = Repository.get(key)

      # Wait for TTL to expire
      :timer.sleep(ttl * 2)

      # Assert - Value is gone after expiration
      assert {:ok, nil} = Repository.get(key)
    end
  end

  describe "update/3" do
    test "updates existing values" do
      # Arrange - Store initial value
      key = "update_key"
      initial_value = %{count: 1}
      Repository.put(key, initial_value)

      # Act - Update the value
      update_fn = fn existing -> %{count: existing.count + 1} end
      assert {:ok, updated} = Repository.update(key, update_fn)

      # Assert - Check the updated value
      assert updated.count == 2
      assert {:ok, retrieved} = Repository.get(key)
      assert retrieved.count == 2
    end

    test "uses default for non-existent keys" do
      # Arrange
      key = "new_key"
      default = %{count: 0}

      # Act - Update non-existent key with default
      update_fn = fn existing -> %{count: existing.count + 5} end
      assert {:ok, updated} = Repository.update(key, update_fn, default)

      # Assert - Check the result used the default
      assert updated.count == 5
    end
  end
end
```

## Integration Test Examples

### Discord Notification Flow

```elixir
# test/integration/flows/notification_flow_test.exs
defmodule WandererNotifier.Integration.Flows.NotificationFlowTest do
  use ExUnit.Case
  import Mox

  alias WandererNotifier.Services.KillProcessor
  alias WandererNotifier.Test.Fixtures.ApiResponses

  # Allow mocks to be used by concurrent processes
  setup :set_mox_global

  # Verify all expectations were met
  setup :verify_on_exit!

  setup do
    # Configure the application to use mocks
    Application.put_env(:wanderer_notifier, :http_client, WandererNotifier.MockHTTP)
    Application.put_env(:wanderer_notifier, :discord_client, WandererNotifier.MockDiscord)

    # Initialize test cache for tracking state
    Cachex.start_link(:test_cache)
    Application.put_env(:wanderer_notifier, :cache_name, :test_cache)

    # Populate cache with tracked systems for the test
    tracked_system = %WandererNotifier.Data.MapSystem{
      id: "30000142",
      name: "Jita",
      tracked: true
    }
    Cachex.put(:test_cache, "tracked_systems", [tracked_system])

    :ok
  end

  test "processes killmail and sends Discord notification for tracked system" do
    # Arrange - Mock ESI API to return character info
    WandererNotifier.MockHTTP
    |> expect(:get, fn url, _headers, _options ->
      assert String.contains?(url, "/characters/")
      {:ok, %{status: 200, body: ApiResponses.esi_character_response()}}
    end)
    |> expect(:get, fn url, _headers, _options ->
      assert String.contains?(url, "/universe/systems/")
      {:ok, %{status: 200, body: %{"name" => "Jita", "security_status" => 0.9}}}
    end)

    # Arrange - Mock Discord client to verify notification
    WandererNotifier.MockDiscord
    |> expect(:send_webhook, fn webhook_url, payload ->
      # Verify webhook URL is correct
      assert webhook_url == System.get_env("DISCORD_WEBHOOK_URL")

      # Verify payload contains expected data
      assert is_map(payload)
      assert Map.has_key?(payload, :embeds)
      [embed] = payload.embeds
      assert String.contains?(embed.title, "Kill in Jita")
      assert String.contains?(embed.description, "Test Character")
      assert embed.color == 0xFF0000  # Red color for kills

      {:ok, %{status: 204}}
    end)

    # Act - Process a killmail message
    killmail = ApiResponses.zkill_message()
    result = KillProcessor.process_killmail(killmail)

    # Assert - Verify result indicates notification was sent
    assert {:ok, :notification_sent} = result
  end
end
```

### Scheduler Integration

```elixir
# test/integration/flows/scheduler_flow_test.exs
defmodule WandererNotifier.Integration.Flows.SchedulerFlowTest do
  use ExUnit.Case
  import Mox

  alias WandererNotifier.Schedulers.IntervalScheduler

  # Allow mocks to be used by concurrent processes
  setup :set_mox_global

  # Verify all expectations were met
  setup :verify_on_exit!

  setup do
    # Configure the application to use mocks
    Application.put_env(:wanderer_notifier, :http_client, WandererNotifier.MockHTTP)
    Application.put_env(:wanderer_notifier, :discord_client, WandererNotifier.MockDiscord)

    # Start a test registry for schedulers
    {:ok, _} = Registry.start_link(keys: :unique, name: WandererNotifier.Test.SchedulerRegistry)
    Application.put_env(:wanderer_notifier, :scheduler_registry, WandererNotifier.Test.SchedulerRegistry)

    :ok
  end

  test "scheduler executes its task and sends notification" do
    # Define a test task function
    test_task = fn ->
      # This represents the result of the scheduled task
      {:ok, %{message: "Task completed", data: [1, 2, 3]}}
    end

    # Mock the Discord client to verify notification is sent
    WandererNotifier.MockDiscord
    |> expect(:send_webhook, fn _webhook_url, payload ->
      # Verify the payload contains task result
      assert is_map(payload)
      assert String.contains?(payload.content, "Task completed")

      {:ok, %{status: 204}}
    end)

    # Create and start a test scheduler
    {:ok, scheduler} = IntervalScheduler.start_link(
      name: :test_scheduler,
      task: test_task,
      interval: 100,  # 100ms interval
      registry: WandererNotifier.Test.SchedulerRegistry
    )

    # Wait for scheduler to execute the task
    :timer.sleep(150)

    # Clean up
    GenServer.stop(scheduler)
  end
end
```

## System Test Examples

### Application Startup Test

```elixir
# test/integration/system/application_test.exs
defmodule WandererNotifier.Integration.System.ApplicationTest do
  use ExUnit.Case
  import Mox

  # Allow mocks to be used by concurrent processes
  setup :set_mox_global

  # Verify all expectations were met
  setup :verify_on_exit!

  setup do
    # Configure application to use mocks
    Application.put_env(:wanderer_notifier, :http_client, WandererNotifier.MockHTTP)
    Application.put_env(:wanderer_notifier, :discord_client, WandererNotifier.MockDiscord)
    Application.put_env(:wanderer_notifier, :websocket_client, WandererNotifier.MockWebSocket)

    # Return application for stopping after test
    %{application: WandererNotifier.Application}
  end

  test "application starts all required components", %{application: app} do
    # Mock HTTP client for startup API calls
    WandererNotifier.MockHTTP
    |> stub(:get, fn url, _headers, _options ->
      cond do
        String.contains?(url, "/systems/tracked") ->
          {:ok, %{status: 200, body: %{"systems" => []}}}
        String.contains?(url, "/characters/tracked") ->
          {:ok, %{status: 200, body: %{"characters" => []}}}
        true ->
          {:ok, %{status: 200, body: %{}}}
      end
    end)

    # Mock WebSocket client for zKillboard connection
    WandererNotifier.MockWebSocket
    |> stub(:start_link, fn _url ->
      {:ok, self()}
    end)

    # Start the application
    {:ok, pid} = app.start(:normal, [])

    # Assert key processes are running
    assert Process.alive?(pid)
    assert Process.whereis(WandererNotifier.Cache.Supervisor) != nil
    assert Process.whereis(WandererNotifier.Schedulers.Supervisor) != nil

    # Verify the application registered expected names
    assert Registry.lookup(WandererNotifier.Registry, "cache_supervisor") != []
    assert Registry.lookup(WandererNotifier.Registry, "scheduler_supervisor") != []

    # Clean up
    app.stop(:normal)
  end

  test "application recovers from API failures during startup", %{application: app} do
    # Mock HTTP client to simulate API failures
    WandererNotifier.MockHTTP
    |> stub(:get, fn url, _headers, _options ->
      if String.contains?(url, "/systems/tracked") do
        # Simulate systems API failure
        {:error, %{reason: "connection_failed"}}
      else
        # Other APIs work normally
        {:ok, %{status: 200, body: %{}}}
      end
    end)

    # Mock WebSocket client
    WandererNotifier.MockWebSocket
    |> stub(:start_link, fn _url ->
      {:ok, self()}
    end)

    # Start the application
    {:ok, pid} = app.start(:normal, [])

    # Assert application started despite API failure
    assert Process.alive?(pid)

    # Clean up
    app.stop(:normal)
  end
end
```

## Running the Tests

### Example Test Running Script

```bash
#!/bin/bash
# run_tests.sh

# Run all tests
echo "Running all tests..."
mix test

# Run specific test files
echo "Running unit tests only..."
mix test test/wanderer_notifier/data

# Run with coverage reporting
echo "Running tests with coverage..."
mix test --cover

# Run with specific tags
echo "Running integration tests only..."
mix test --only integration
```

### Test Environment Setup

```elixir
# config/test.exs
import Config

config :wanderer_notifier,
  # Use test-specific configuration
  http_client: WandererNotifier.MockHTTP,
  discord_client: WandererNotifier.MockDiscord,
  websocket_client: WandererNotifier.MockWebSocket,
  cache_name: :test_cache,

  # Faster timeouts for tests
  api_timeout: 100,

  # Test-specific feature flags
  features: %{
    "send_discord_notifications" => true,
    "track_character_changes" => true,
    "generate_tps_charts" => false  # Disable for tests
  }

# Configure logger for test environment
config :logger, level: :warn
```
