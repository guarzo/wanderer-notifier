# WandererNotifier Testing Strategy

This document outlines a comprehensive testing strategy for the WandererNotifier application, designed to ensure code quality, correctness, and reliability.

## Testing Philosophy

The testing approach for WandererNotifier follows these key principles:

1. **Align with Architecture**: Tests should reflect the component-based, event-driven, and functional architecture of the application.
2. **Isolate Pure Logic**: Pure functions should be tested in isolation with predictable inputs and outputs.
3. **Mock External Dependencies**: External services and side effects should be properly mocked.
4. **Cover Critical Paths**: Critical notification and data processing flows should have comprehensive test coverage.
5. **Enable Refactoring**: Tests should verify behavior, not implementation details, to enable safe refactoring.

## Testing Layers

### 1. Unit Tests

Focus on testing the smallest testable parts of the application in isolation:

- **Pure Functions**: Data transformations, business logic, and helper utilities
- **Data Structures**: Validation, normalization, and conversions between types
- **State Management**: Behavior of individual stateful components

### 2. Component Tests

Test individual components with mocked dependencies:

- **API Clients**: Test with mocked HTTP responses
- **Cache Repository**: Test with mocked storage layer
- **Formatters**: Test with known inputs and expected outputs
- **Schedulers**: Test with controlled timing and mocked execution contexts

### 3. Integration Tests

Test interactions between related components:

- **API Client + Data Processor**: Test data acquisition and transformation
- **Processor + Notifier**: Test notification determination and delivery
- **Scheduler + Task**: Test scheduled task execution

### 4. System Tests

Test complete application flows with mocked external dependencies:

- **Kill Notification Flow**: From WebSocket message to Discord notification
- **Character Tracking Flow**: From API data to notification
- **System Tracking Flow**: From API data to notification
- **Chart Generation Flow**: From data to chart delivery

## Test Directory Structure

```
test/
├── support/
│   ├── mocks/             # Mock implementations
│   ├── fixtures/          # Sample data files
│   └── helpers/           # Test helper functions
├── wanderer_notifier/
│   ├── api/               # API client tests
│   ├── cache/             # Cache repository tests
│   ├── core/              # Core module tests
│   ├── data/              # Data structure tests
│   ├── discord/           # Discord integration tests
│   ├── notifiers/         # Notifier implementation tests
│   ├── schedulers/        # Scheduler tests
│   └── services/          # Service tests
└── integration/           # Cross-component tests
    ├── flows/             # End-to-end flow tests
    └── system/            # System behavior tests
```

## Implementation Plan

### Phase 1: Test Infrastructure

1. **Create Test Helper Module**

   Set up ExUnit and define mocks for external dependencies:

   ```elixir
   # test/test_helper.exs
   ExUnit.start()

   # Define mocks for external dependencies
   Mox.defmock(WandererNotifier.MockHTTP, for: WandererNotifier.HTTP.Behaviour)
   Mox.defmock(WandererNotifier.MockCache, for: WandererNotifier.Cache.Behaviour)
   Mox.defmock(WandererNotifier.MockNotifier, for: WandererNotifier.NotifierBehaviour)
   ```

2. **Create Fixtures and Test Data**

   Create sample data files for:

   - API responses (Map API, ESI, zKillboard, Corp Tools)
   - Structured data (Character, MapSystem, Killmail)
   - Notification payloads (Discord embeds, webhooks)

3. **Define Interfaces for Mockable Components**

   Ensure all components that interact with external services implement behavior modules for mockability:

   ```elixir
   # lib/wanderer_notifier/http/behaviour.ex
   defmodule WandererNotifier.HTTP.Behaviour do
     @callback get(String.t(), list(), list()) :: {:ok, map()} | {:error, term()}
     @callback post(String.t(), term(), list(), list()) :: {:ok, map()} | {:error, term()}
   end
   ```

### Phase 2: Core Component Tests

1. **Data Structure Tests**

   Test validation, normalization, and transformations:

   ```elixir
   # test/wanderer_notifier/data/character_test.exs
   defmodule WandererNotifier.Data.CharacterTest do
     use ExUnit.Case

     alias WandererNotifier.Data.Character

     test "validates required fields" do
       # Test code
     end

     test "normalizes corporation data" do
       # Test code
     end
   end
   ```

2. **API Client Tests**

   Test URL construction, response handling, and error cases:

   ```elixir
   # test/wanderer_notifier/api/map/systems_client_test.exs
   defmodule WandererNotifier.Api.Map.SystemsClientTest do
     use ExUnit.Case
     import Mox

     alias WandererNotifier.Api.Map.SystemsClient

     setup :verify_on_exit!

     test "fetches systems with valid response" do
       # Set up mock expectations
       # Test code
     end

     test "handles error response" do
       # Set up mock expectations for error
       # Test code
     end
   end
   ```

3. **Cache Repository Tests**

   Test caching behavior, TTL, and retrieval:

   ```elixir
   # test/wanderer_notifier/cache/repository_test.exs
   defmodule WandererNotifier.Cache.RepositoryTest do
     use ExUnit.Case

     alias WandererNotifier.Cache.Repository

     test "stores and retrieves data" do
       # Test code
     end

     test "respects TTL for cached items" do
       # Test code with time manipulation
     end
   end
   ```

### Phase 3: Service and Flow Tests

1. **Notification Determination Tests**

   Test business rules for notification triggers:

   ```elixir
   # test/wanderer_notifier/services/notification_determiner_test.exs
   defmodule WandererNotifier.Services.NotificationDeterminerTest do
     use ExUnit.Case

     alias WandererNotifier.Services.NotificationDeterminer

     test "determines notification for tracked system" do
       # Test code
     end

     test "skips notification for untracked system" do
       # Test code
     end
   end
   ```

2. **Formatter Tests**

   Test creation of properly formatted notifications:

   ```elixir
   # test/wanderer_notifier/discord/formatter_test.exs
   defmodule WandererNotifier.Discord.FormatterTest do
     use ExUnit.Case

     alias WandererNotifier.Discord.Formatter

     test "formats kill notification with proper colors and fields" do
       # Test code
     end

     test "includes links to zKillboard in notification" do
       # Test code
     end
   end
   ```

3. **Scheduler Tests**

   Test scheduling logic and task execution:

   ```elixir
   # test/wanderer_notifier/schedulers/interval_scheduler_test.exs
   defmodule WandererNotifier.Schedulers.IntervalSchedulerTest do
     use ExUnit.Case

     alias WandererNotifier.Schedulers.IntervalScheduler

     test "schedules execution at proper intervals" do
       # Test code with mocked timer functions
     end

     test "executes task function with proper arguments" do
       # Test code
     end
   end
   ```

### Phase 4: Integration Tests

1. **Kill Processing Flow Tests**

   Test the complete flow from WebSocket message to notification:

   ```elixir
   # test/integration/flows/kill_processing_test.exs
   defmodule WandererNotifier.Integration.Flows.KillProcessingTest do
     use ExUnit.Case
     import Mox

     setup :verify_on_exit!

     test "processes kill message and sends notification for tracked system" do
       # Set up mocks for complete flow
       # Test integration of multiple components
     end
   end
   ```

2. **Chart Generation Flow Tests**

   Test the flow from data to chart delivery:

   ```elixir
   # test/integration/flows/chart_generation_test.exs
   defmodule WandererNotifier.Integration.Flows.ChartGenerationTest do
     use ExUnit.Case
     import Mox

     setup :verify_on_exit!

     test "generates TPS chart and delivers to Discord" do
       # Set up mocks for complete flow
       # Test integration of chart generation components
     end
   end
   ```

### Phase 5: System Tests

1. **End-to-End Tests**

   Test application behavior with mocked external dependencies:

   ```elixir
   # test/integration/system/application_test.exs
   defmodule WandererNotifier.Integration.System.ApplicationTest do
     use ExUnit.Case

     test "initializes all components on startup" do
       # Test application startup with mocked components
     end

     test "gracefully handles API failures" do
       # Test resilience and recovery
     end
   end
   ```

## Testing Tools and Libraries

| Tool            | Purpose                                   |
| --------------- | ----------------------------------------- |
| **ExUnit**      | Standard Elixir testing framework         |
| **Mox**         | Mocking library for external dependencies |
| **ExCoveralls** | Test coverage reporting                   |
| **Bypass**      | HTTP request mocking                      |
| **StreamData**  | Property-based testing                    |

## Continuous Integration

Configure GitHub Actions to run tests on every push and pull request:

```yaml
# .github/workflows/test.yml
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

## Testing Standards

1. **Test Naming**

   - Use descriptive names that explain the behavior being tested
   - Follow pattern: `"[function_name] [scenario] [expected result]"`

2. **Test Structure**

   - Arrange: Set up test data and expectations
   - Act: Execute the code being tested
   - Assert: Verify the results

3. **Code Coverage Goals**
   - Core business logic: 90%+ coverage
   - API clients and notifications: 80%+ coverage
   - Overall application: 75%+ coverage

## Implementation Timeline

| Phase | Focus                           | Timeline  |
| ----- | ------------------------------- | --------- |
| 1     | Test infrastructure setup       | Week 1    |
| 2     | Core component tests            | Weeks 2-3 |
| 3     | Service and flow tests          | Weeks 4-5 |
| 4     | Integration tests               | Week 6    |
| 5     | System tests and CI integration | Week 7    |

## Conclusion

This testing strategy provides a comprehensive approach to ensuring the quality and reliability of the WandererNotifier application. By following a layered testing approach that aligns with the application's architecture, we can maintain high confidence in the codebase while enabling future development and refactoring.
