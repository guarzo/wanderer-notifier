# WandererNotifier Tests

This directory contains tests for the WandererNotifier application.

## Directory Structure

```
test/
├── support/                 # Support modules for testing
│   ├── fixtures/            # Sample data files
│   ├── mocks/               # Mock implementations
│   └── helpers/             # Test helper functions
├── wanderer_notifier/       # Unit and component tests
│   ├── api/                 # API client tests
│   ├── cache/               # Cache repository tests
│   ├── http/                # HTTP client tests
│   ├── data/                # Data structure tests
│   ├── discord/             # Discord integration tests
│   ├── helpers/             # Helper function tests
│   ├── notifiers/           # Notifier implementation tests
│   ├── schedulers/          # Scheduler tests
│   └── services/            # Service tests
├── integration/             # Cross-component tests
│   ├── flows/               # End-to-end flow tests
│   └── system/              # System behavior tests
└── test_helper.exs          # Test configuration and setup
```

## Current Test Coverage

| Component        | Type        | Status      |
| ---------------- | ----------- | ----------- |
| HTTP Client      | Mock        | Implemented |
| Cache Repository | Mock        | Implemented |
| API Client       | Integration | Implemented |
| Basic Helper     | Unit        | Implemented |

## Running Tests

```bash
# Run all tests
mix test

# Run a specific test file
mix test test/wanderer_notifier/http/http_test.exs

# Run with code coverage report
mix test --cover
```

## Mocking

The tests use the Mox library to mock external dependencies. The following mocks are available:

- `WandererNotifier.MockHTTP` - For mocking HTTP requests
- `WandererNotifier.MockCache` - For mocking cache operations
- `WandererNotifier.MockDiscord` - For mocking Discord operations
- `WandererNotifier.MockWebSocket` - For mocking WebSocket operations

## Fixtures

Sample data for tests is available in `test/support/fixtures/api_responses.ex`. Current fixtures include:

- Map API system data
- ESI character responses
- zKillboard killmail messages

## Adding New Tests

When adding new tests:

1. Follow the existing pattern and directory structure
2. Use the appropriate mocks for external dependencies
3. Use fixtures for sample data
4. Follow the AAA pattern (Arrange, Act, Assert)
5. Ensure tests are independent and don't rely on side effects

## Test Environment

The test environment configuration is in `config/test.exs`. It includes:

- Mocked dependencies instead of real ones
- Faster timeouts for tests
- Test-specific feature flags

## Further Documentation

For more details on the testing strategy and example implementations, see:

- `docs/testing/testing-strategy.md`
- `docs/testing/example-tests.md`
- `docs/testing/getting-started.md`

```
mix archive.install hex bunt
```