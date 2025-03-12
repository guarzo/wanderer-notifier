# License and Bot Registration Test Plan

This document outlines the test plan for the license validation and bot registration feature in WandererNotifier.

## Components to Test

1. **Config Module** (`WandererNotifier.Config`)
   - Environment variable access
   - Default values
   - Error handling for missing required variables

2. **License Manager Client** (`WandererNotifier.LicenseManager.Client`)
   - API communication
   - Response handling
   - Error handling

3. **License Module** (`WandererNotifier.License`)
   - License validation
   - Feature flag checking
   - Periodic refresh
   - State management

4. **Bot Registration Module** (`WandererNotifier.BotRegistration`)
   - Registration process
   - Error handling
   - Conditional registration based on configuration

5. **Features Module** (`WandererNotifier.Features`)
   - Feature flag checking
   - Conditional execution based on features
   - Premium tier detection

6. **Application Integration** (`WandererNotifier.Application`)
   - Startup validation
   - Error handling during startup
   - Graceful degradation with invalid license

## Test Scenarios

### Config Module Tests

- **Environment Variable Access**
  - Test that each environment variable can be accessed
  - Test behavior when variables are not set
  - Test behavior when variables are set to empty strings

- **Error Handling**
  - Test that `get_env!/1` raises an error when the variable is not set
  - Test that `get_env/1` returns nil when the variable is not set

### License Manager Client Tests

- **License Validation**
  - Test successful license validation
  - Test validation with invalid license key
  - Test validation with nonexistent license key
  - Test validation with API errors (401, 404, 500)
  - Test validation with network errors
  - Test validation with invalid JSON response

- **Bot Registration**
  - Test successful bot registration
  - Test registration with already registered bot
  - Test registration with API errors (401, 409, 500)
  - Test registration with network errors
  - Test registration with invalid JSON response

### License Module Tests

- **License Validation**
  - Test validation with valid license
  - Test validation with invalid license
  - Test validation with missing license key
  - Test validation with API errors

- **Feature Flag Checking**
  - Test checking for enabled features
  - Test checking for disabled features
  - Test checking for features with invalid license

- **Premium Tier Detection**
  - Test premium tier detection with premium license
  - Test premium tier detection with enterprise license
  - Test premium tier detection with basic license
  - Test premium tier detection with invalid license

- **Periodic Refresh**
  - Test that the license is refreshed periodically
  - Test that the license state is updated after refresh

### Bot Registration Module Tests

- **Registration Process**
  - Test successful registration
  - Test registration with already registered bot
  - Test registration with API errors
  - Test registration with missing license key
  - Test registration with missing registration token

### Features Module Tests

- **Feature Flag Checking**
  - Test checking for enabled features
  - Test checking for disabled features

- **Conditional Execution**
  - Test conditional execution with enabled features
  - Test conditional execution with disabled features
  - Test conditional execution with premium tier
  - Test conditional execution with non-premium tier

### Application Integration Tests

- **Startup Validation**
  - Test startup with valid license
  - Test startup with invalid license
  - Test startup with missing license key

- **Bot Registration During Startup**
  - Test registration during startup with valid license
  - Test registration during startup with invalid license
  - Test registration during startup with missing registration token

## Test Implementation

The test implementation is organized into the following files:

1. `test/test_helper.exs` - Sets up the test environment and defines mocks
2. `test/wanderer_notifier/support/test_helpers.ex` - Provides helper functions for testing
3. `test/wanderer_notifier/config_test.exs` - Tests for the Config module
4. `test/wanderer_notifier/license_manager/client_test.exs` - Tests for the License Manager Client
5. `test/wanderer_notifier/license_test.exs` - Tests for the License module
6. `test/wanderer_notifier/bot_registration_test.exs` - Tests for the Bot Registration module
7. `test/wanderer_notifier/features_test.exs` - Tests for the Features module
8. `test/wanderer_notifier/application_test.exs` - Tests for the Application integration

## Running the Tests

To run the tests, use the following command:

```bash
mix test
```

To run a specific test file:

```bash
mix test test/wanderer_notifier/license_test.exs
```

To run tests with coverage:

```bash
mix test --cover
```

## Test Dependencies

The tests depend on the following libraries:

- **ExUnit** - The built-in Elixir testing framework
- **Mox** - For mocking dependencies in tests

## Continuous Integration

These tests should be integrated into the CI/CD pipeline to ensure that the license and bot registration feature continues to work as expected with future changes.

## Manual Testing

In addition to automated tests, the following manual tests should be performed:

1. Test with a real license key in a development environment
2. Test with an invalid license key in a development environment
3. Test with a real bot registration token in a development environment
4. Test the application startup with various combinations of environment variables 