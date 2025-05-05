#!/bin/bash

# Setup Test Environment Script for WandererNotifier
set -e  # Exit on error

echo "Setting up test environment for WandererNotifier..."

# Create main test directories
echo "Creating test directory structure..."
mkdir -p test/support/{mocks,fixtures,helpers}
mkdir -p test/wanderer_notifier/{api,cache,core,data,discord,notifiers,schedulers,services}
mkdir -p test/integration/{flows,system}

# Create test helper
echo "Creating test_helper.exs..."
cat > test/test_helper.exs << 'EOL'
ExUnit.start()

# Define mocks for external dependencies
Mox.defmock(WandererNotifier.MockHTTP, for: WandererNotifier.HttpClient.Behaviour)
Mox.defmock(WandererNotifier.MockCache, for: WandererNotifier.Data.Cache.Behaviour)
Mox.defmock(WandererNotifier.MockDiscord, for: WandererNotifier.Discord.Behaviour)
Mox.defmock(WandererNotifier.MockWebSocket, for: WandererNotifier.WebSocket.Behaviour)

# Set Mox global mode for integration tests where needed
Application.put_env(:mox, :verify_on_exit, true)
EOL

# Create HTTP behavior module
echo "Creating HTTP behaviour module..."
mkdir -p lib/wanderer_notifier/http
cat > lib/wanderer_notifier/http/behaviour.ex << 'EOL'
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
EOL

# Create test environment configuration
echo "Creating test environment configuration..."
mkdir -p config
cat > config/test.exs << 'EOL'
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
EOL

# Create test fixtures
echo "Creating test fixtures..."
mkdir -p test/support/fixtures
cat > test/support/fixtures/api_responses.ex << 'EOL'
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
EOL

# Create sample test
echo "Creating sample test..."
mkdir -p test/wanderer_notifier/helpers
cat > test/wanderer_notifier/helpers/sample_test.exs << 'EOL'
defmodule WandererNotifier.Helpers.SampleTest do
  use ExUnit.Case
  
  test "basic assertion works" do
    assert 1 + 1 == 2
  end
end
EOL

# Update mix.exs to include test coverage
echo "Checking if ExCoveralls is in dependencies..."
if ! grep -q "excoveralls" mix.exs; then
  echo "Please add ExCoveralls to your mix.exs dependencies:"
  echo "
  defp deps do
    [
      # ... existing deps
      {:excoveralls, \"~> 0.14\", only: :test},
    ]
  end

  def project do
    [
      # ... existing project config
      test_coverage: [tool: ExCoveralls],
      preferred_cli_env: [
        coveralls: :test,
        \"coveralls.detail\": :test,
        \"coveralls.post\": :test,
        \"coveralls.html\": :test
      ]
    ]
  end
  "
fi

# Create GitHub Actions workflow for CI
echo "Creating GitHub Actions workflow..."
mkdir -p .github/workflows
cat > .github/workflows/test.yml << 'EOL'
name: Test

on:
  push:
    branches: [ main ]
  pull_request:
    branches: [ main ]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v2
      - name: Set up Elixir
        uses: erlef/setup-beam@v1
        with:
          elixir-version: '1.14.x'
          otp-version: '25.x'
      - name: Install dependencies
        run: mix deps.get
      - name: Run tests
        run: mix test
      - name: Run code quality checks
        run: mix credo
EOL

# Make this script executable
chmod +x scripts/setup_test_env.sh

echo "Test environment setup complete!"
echo "You can now run: mix test"
echo "For more information, see the testing documentation in docs/testing/" 