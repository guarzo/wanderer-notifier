# Getting Started with Testing WandererNotifier

This guide will help you quickly set up the testing infrastructure and create your first tests for the WandererNotifier application.

## Step 1: Create Test Directory Structure

First, create the necessary test directory structure:

```bash
# Create main test directories
mkdir -p test/support/{mocks,fixtures,helpers}
mkdir -p test/wanderer_notifier/{api,cache,core,data,discord,notifiers,schedulers,services}
mkdir -p test/integration/{flows,system}

# Create basic test_helper.exs file
touch test/test_helper.exs
```

## Step 2: Set Up Test Helper

Add the following content to `test/test_helper.exs`:

```elixir
ExUnit.start()

# Define mocks for external dependencies
Mox.defmock(WandererNotifier.MockHTTP, for: WandererNotifier.HTTP.Behaviour)
Mox.defmock(WandererNotifier.MockCache, for: WandererNotifier.Cache.Behaviour)
Mox.defmock(WandererNotifier.MockDiscord, for: WandererNotifier.Discord.Behaviour)
Mox.defmock(WandererNotifier.MockWebSocket, for: WandererNotifier.WebSocket.Behaviour)
```

## Step 3: Create Test Environment Configuration

Create a test-specific configuration file:

```bash
# Create test environment config
touch config/test.exs
```

Add the following content to `config/test.exs`:

```elixir
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

## Step 4: Define Behaviors for Mockable Components

Create behavior modules for components that need to be mocked:

```bash
# Create HTTP behavior module
mkdir -p lib/wanderer_notifier/http
touch lib/wanderer_notifier/http/behaviour.ex
```

Add the following content to `lib/wanderer_notifier/http/behaviour.ex`:

```elixir
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

## Step 5: Create Test Fixtures

Create a module for test fixtures:

```bash
# Create fixtures directory and file
mkdir -p test/support/fixtures
touch test/support/fixtures/api_responses.ex
```

Add the following content to `test/support/fixtures/api_responses.ex`:

```elixir
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

## Step 6: Create Your First Test

Create a simple test for a data structure:

```bash
# Create directory for data structure tests
mkdir -p test/wanderer_notifier/data
touch test/wanderer_notifier/data/map_system_test.exs
```

Add a basic test implementation (adjust based on your actual implementation):

```elixir
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
  end
end
```

## Step 7: Run Tests

Now you can run your tests:

```bash
# Run all tests
mix test

# Run a specific test file
mix test test/wanderer_notifier/data/map_system_test.exs

# Run with coverage
mix test --cover
```

## Step 8: Add More Tests

Continue adding tests following the patterns in the example-tests.md document:

1. Start with unit tests for data structures and pure functions
2. Add component tests with mocked dependencies
3. Create integration tests for testing flows between components
4. Add system tests for complete application behavior

## Additional Setup

### Add a CI Configuration

Create a GitHub Actions workflow for CI:

```bash
# Create GitHub Actions directory
mkdir -p .github/workflows
touch .github/workflows/test.yml
```

Add the following content to `.github/workflows/test.yml`:

```yaml
name: Test

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v2
      - name: Set up Elixir
        uses: erlef/setup-beam@v1
        with:
          elixir-version: "1.14.x"
          otp-version: "25.x"
      - name: Install dependencies
        run: mix deps.get
      - name: Run tests
        run: mix test
      - name: Run code quality checks
        run: mix credo
```

### Add Test Coverage Tool

Add the ExCoveralls package to your dependencies in `mix.exs`:

```elixir
defp deps do
  [
    # ... existing deps
    {:excoveralls, "~> 0.14", only: :test},
  ]
end
```

Configure ExCoveralls in your `mix.exs`:

```elixir
def project do
  [
    # ... existing project config
    test_coverage: [tool: ExCoveralls],
    preferred_cli_env: [
      coveralls: :test,
      "coveralls.detail": :test,
      "coveralls.post": :test,
      "coveralls.html": :test
    ]
  ]
end
```

Now you can generate coverage reports:

```bash
# Generate HTML coverage report
mix coveralls.html
```

## Test Tagging

You can use tags to categorize your tests:

```elixir
@tag :unit
test "my unit test" do
  # test code
end

@tag :integration
test "my integration test" do
  # test code
end
```

And then run specific categories:

```bash
# Run only unit tests
mix test --only unit

# Exclude integration tests
mix test --exclude integration
```

## Next Steps

1. Review the full testing strategy in `docs/testing/testing-strategy.md`
2. See example test implementations in `docs/testing/example-tests.md`
3. Start implementing tests for your core components
4. Gradually add more comprehensive tests as you become familiar with the testing infrastructure
