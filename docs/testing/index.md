# WandererNotifier Testing Documentation

This directory contains documentation and resources for testing the WandererNotifier application.

## Overview

WandererNotifier uses a comprehensive testing approach to ensure code quality and reliability. The testing architecture follows a layered approach that aligns with the component-based, event-driven, and functional architecture of the application.

## Contents

- [Testing Strategy](testing-strategy.md) - Detailed documentation of the testing philosophy, approach, and architecture
- [Example Tests](example-tests.md) - Example test implementations for different components
- [Getting Started](getting-started.md) - Step-by-step guide to set up the testing environment

## Quick Start

To quickly set up the testing environment, run:

```bash
# Make the script executable if needed
chmod +x scripts/setup_test_env.sh

# Run the setup script
./scripts/setup_test_env.sh
```

This will create the necessary test directory structure, fixtures, and sample tests to get you started.

## Test Structure

The tests are organized into the following layers:

1. **Unit Tests** - Testing individual functions and modules in isolation
2. **Component Tests** - Testing components with mocked dependencies
3. **Integration Tests** - Testing interactions between components
4. **System Tests** - Testing complete application flows

## Key Testing Tools

- **ExUnit** - Standard Elixir testing framework
- **Mox** - Mocking library for external dependencies
- **ExCoveralls** - Test coverage reporting

## Best Practices

1. **Follow the AAA pattern**:

   - Arrange: Set up test data and expectations
   - Act: Execute the code being tested
   - Assert: Verify the results

2. **Use descriptive test names** that explain what's being tested and the expected outcome

3. **Isolate tests** to prevent dependencies between them

4. **Mock external dependencies** to keep tests fast and reliable

5. **Use fixtures** for common test data

6. **Tag tests** for organization and selective execution:
   ```elixir
   @tag :unit
   @tag :integration
   @tag :slow
   ```

## Directory Structure

```
test/
├── support/                 # Support modules for testing
│   ├── mocks/               # Mock implementations
│   ├── fixtures/            # Sample data files
│   └── helpers/             # Test helper functions
├── wanderer_notifier/       # Unit and component tests
│   ├── api/                 # API client tests
│   ├── cache/               # Cache repository tests
│   ├── core/                # Core module tests
│   ├── data/                # Data structure tests
│   ├── discord/             # Discord integration tests
│   ├── notifiers/           # Notifier implementation tests
│   ├── schedulers/          # Scheduler tests
│   └── services/            # Service tests
└── integration/             # Cross-component tests
    ├── flows/               # End-to-end flow tests
    └── system/              # System behavior tests
```

## Running Tests

```bash
# Run all tests
mix test

# Run a specific test file
mix test test/wanderer_notifier/data/map_system_test.exs

# Run tests with a specific tag
mix test --only integration

# Generate coverage report
mix coveralls.html
```

## Adding New Tests

When adding new tests, follow these steps:

1. Determine which layer the test belongs to (unit, component, integration, system)
2. Create the test file in the appropriate directory
3. Follow the patterns in the example tests
4. Ensure proper setup and teardown of test resources

## Continuous Integration

Tests are automatically run in the CI pipeline for every pull request and push to the main branch. Make sure all tests pass before merging code.
