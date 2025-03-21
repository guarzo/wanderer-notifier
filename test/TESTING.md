# Testing Approach for Wanderer Notifier

This document describes the testing approach for the Wanderer Notifier application. It covers the testing structure, how to run tests, and guidelines for writing new tests.

## Testing Structure

The Wanderer Notifier test suite is organized into several categories:

1. **Discord Notification Tests**

   - Tests for sending different types of Discord notifications
   - Mock tests for HTTP interactions with Discord API

2. **API Client Tests**

   - ZKillboard API clients
   - ESI (EVE Swagger Interface) API clients
   - Map API clients

3. **Formatter Tests**
   - Tests for data formatting
   - Tests for notification structure formatting

## Running Tests

The test suite can be run using several commands:

```bash
# Run all tests
make test

# Run all tests with trace output
make test.all

# Run specific test categories
./test/run_tests.sh

# Run a specific test file
mix test test/wanderer_notifier/discord/notifier_test.exs
```

## Writing New Tests

When writing new tests for the application, follow these guidelines:

### Test Case Structure

- Use `WandererNotifier.TestCase` as the base for your test modules. It provides common helpers and setup.
- Group related tests using `describe` blocks.
- Keep test functions focused on testing a single behavior.

### Mocking External Services

The test suite uses [Mox](https://hexdocs.pm/mox/Mox.html) to mock external dependencies. The following mocks are defined:

1. `WandererNotifier.MockHTTPClient` - For HTTP requests
2. `WandererNotifier.MockDiscordAPI` - For Discord API interactions
3. `WandererNotifier.MockESIService` - For EVE Swagger Interface interactions

Example of mocking an HTTP request:

```elixir
# In your test setup
MockHTTPClient
|> expect(:get, fn url, _headers ->
  assert String.contains?(url, "expected_path")
  {:ok, %HTTPoison.Response{status_code: 200, body: Jason.encode!(response_data)}}
end)
```

### Test Data Helpers

The `WandererNotifier.TestCase` module provides several helpers for generating test data:

- `sample_killmail/0` - Returns sample killmail data
- `sample_system/0` - Returns sample system data
- `sample_character/0` - Returns sample character data

Use these helpers to keep test data consistent across test modules.

### Test Environment

Tests run in the `:test` environment. The test environment is set up automatically by `WandererNotifier.TestCase`. You can override environment variables in your tests if needed:

```elixir
Application.put_env(:wanderer_notifier, :some_config, "test_value")
```

## Adding New Test Categories

When adding tests for a new feature or service:

1. Create a new test module in the appropriate directory.
2. Use `WandererNotifier.TestCase` as the base module.
3. Add the test path to `test/run_tests.sh` if it's a new category.
4. Consider adding a specific make target for the new test category.

## Test Coverage

We're aiming for good test coverage of critical functionality, especially:

1. Notification generation and formatting
2. API client interactions
3. Error handling

Use `mix test --cover` to generate a coverage report.

## Continuous Integration

The test suite is designed to run in CI environments with minimal setup. The tests are written to avoid actual external service calls by using mocks.
