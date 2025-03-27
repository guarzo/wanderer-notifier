# Refactoring & Troubleshooting Tasks

- [ ] Review features.ex -- remove premium, how are we using the features?

## API Clients and HTTP Patterns
- [ ] Create a shared HTTP client module (`WandererNotifier.Api.HTTPClient`)
  - [ ] Implement helper functions for GET/POST requests with built-in retries and exponential backoff.
  - [ ] Standardize response parsing (JSON decoding, status code checking) and error wrapping.
- [ ] Centralize URL construction into a dedicated module or macros.
- [ ] Define a behaviour for API clients to enforce implementation of common functions (e.g., `fetch/1`, `validate_response/1`, `handle_error/1`).

## Error Handling and Logging
- [ ] Create a unified error module (`WandererNotifier.Error`)
  - [ ] Standardize error creation for API errors, validation errors, etc.
  - [ ] Provide logging functions that automatically enrich log messages with contextual data (e.g., endpoint, parameters, correlation IDs).
- [ ] Wrap repeated error handling patterns in helper functions or macros to reduce duplication.
- [ ] Enhance logging across modules to include meaningful context for easier debugging.

## Configuration Management
- [ ] Establish a base configuration file for common settings shared across environments.
- [ ] Create a dedicated configuration module (`WandererNotifier.Config`) for environment variable parsing.
  - [ ] Implement a function like `get_env/3` to retrieve and parse environment variables (e.g., converting to integer or boolean).
  - [ ] Provide functions for feature flag checks, including legacy fallback logic.
- [ ] Document configuration dependencies and relationships to clarify which settings affect which features.

## Caching Strategy
- [ ] Build a dedicated caching utility module (`WandererNotifier.Cache.Utils`)
  - [ ] Create helper functions for consistent cache key naming and TTL management.
  - [ ] Standardize error handling for cache operations.
- [ ] Centralize TTL values in configuration rather than hardcoding them across modules.

## Scheduler Modules & Registration
- [ ] Refine the `BaseScheduler` module to encapsulate common scheduling logic.
  - [ ] Include standardized error handling, logging, and a generic retry mechanism.
- [ ] Define a common behaviour for schedulers to enforce a uniform callback interface.
- [ ] Isolate task-specific logic from scheduling logic into separate functions or modules.
- [ ] **Scheduler Registration Troubleshooting:**
  - [ ] Verify that `WandererNotifier.Schedulers.Registry` is properly started.
    - [ ] In IEx, run: `Process.whereis(WandererNotifier.Schedulers.Registry)`
    - [ ] Check registry state with: `:sys.get_state(WandererNotifier.Schedulers.Registry)`
    - [ ] Monitor registry registration calls with: `:sys.trace(WandererNotifier.Schedulers.Registry, true)`
  - [ ] Examine the scheduler startup process:
    - [ ] Check supervisor tree for schedulers using: `Supervisor.which_children(WandererNotifier.Schedulers.Supervisor)`
    - [ ] Verify individual scheduler processes exist (e.g., for `ActivityChartScheduler`, `SystemUpdateScheduler`).
    - [ ] Check logs for any crash reports or registration errors.
  - [ ] Add detailed logging in the `BaseScheduler.__using__` macro to track initialization.
  - [ ] Add debug logging in `SchedulerRegistry.register/1` to confirm registration is being called.
  - [ ] Review feature flag settings that control scheduler activation (e.g., `kill_charts_enabled?()`, `map_charts_enabled?()`).
  - [ ] Address potential timing issues ensuring the registry is ready before schedulers register.
  - [ ] Consider adding retry logic for scheduler registration if the initial attempt fails.
  - [ ] Optionally, evaluate auto-discovery or configuration-based approaches for the dashboard.

## Notification Services
- [ ] Define a notification behaviour that specifies a common interface (e.g., `prepare_message/1`, `send_notification/1`).
- [ ] Extract common formatting functions (e.g., for creating Discord embeds) into a shared module (`WandererNotifier.Notifications.Formatter`).
- [ ] Implement a standardized fallback mechanism for notification delivery failures.

## Helper Modules and Code Organization
- [ ] Review and consolidate overlapping helper modules.
- [ ] Standardize naming conventions for helper functions to improve clarity.
- [ ] Enhance documentation for all helper modules and functions with clear `@doc` annotations.

## Application Startup and Supervisor Tree
- [ ] Review and refactor the `WandererNotifier.Application` startup code:
  - [ ] Ensure the supervision tree is clearly defined and follows a consistent strategy (e.g., one_for_one) for independent children.
  - [ ] Consolidate and centralize startup logic, including configuration initialization, database connections, and external API health checks.
  - [ ] Implement uniform logging during startup to record the initialization status of key components.
  - [ ] Verify that child specifications are properly defined with consistent restart strategies.
  - [ ] Add startup health checks and environment validation (e.g., ensuring all required environment variables are set) to fail fast if necessary.
  - [ ] Consider splitting large supervisors into domain-specific supervisors for improved modularity.
- [ ] Improve application shutdown and release handling:
  - [ ] Ensure that all processes terminate gracefully on shutdown.
  - [ ] Implement any necessary cleanup tasks during application shutdown.

## Additional Critical & High Priority Action Items

### Technical Debt
- [ ] Remove backwards compatibility layers in notifier modules.
  - [ ] Audit usages of old non-namespaced modules.
  - [ ] Remove proxy modules if migration is complete.
  - [ ] Update documentation to reflect current namespaces.
- [ ] Replace deprecated API calls in `discord/notifier.ex`.
- [ ] Consolidate duplicate code in notification formatters.
- [ ] Refactor `config.exs` to use proper configuration patterns.
- [ ] Clean up unused variables and functions.
- [ ] Standardize cache key formats.

### Testing & Quality
- [ ] Increase unit test coverage across core functionality.
- [ ] Add test suites for edge cases.
- [ ] Add benchmarks for critical functions.
- [ ] Document test environment setup.
- [ ] Review test timeouts and consider making them configurable.
- [ ] Standardize feature flag testing approach.

### Architecture Improvements
- [ ] Split large modules (e.g., `MapSystem`, `Character`) into more focused components.
- [ ] Implement data versioning.
- [ ] Add audit logging.
- [ ] Review and optimize database schema design.

### Version Management
- [ ] Add `git_ops` for semantic versioning.
  - [ ] Add dependency to `mix.exs`.
  - [ ] Configure for automated CHANGELOG generation.
  - [ ] Set up commit message conventions.
- [ ] Create a `VERSION` file at the project root.
- [ ] Automate version bumping based on Git commits.
- [ ] Create a `.tool-versions` file for version management.
- [ ] Update Dockerfile to use environment variables for versions.

### Dependencies
- [ ] Migrate from `mock` to `Mox` for testing.
  - [ ] Audit current usage of `mock` in tests.
  - [ ] Create a migration plan for test updates.
  - [ ] Update tests to use `Mox` exclusively.
  - [ ] Remove `mock` dependency.
- [ ] Document the reason for any dependency overrides (e.g., `ranch` in `mix.exs`).

### Documentation
- [ ] Create high-level project documentation in the docs folder
- [ ] Create a troubleshooting guide.
- [ ] Document all feature flags and their purposes.
- [ ] Document all environment variables in the README and index.md (GH-pages source)

### Feature Enhancements
- [ ] Add support for more notification channels per notification type
