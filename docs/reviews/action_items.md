# Action Items

## Critical Priority

### Security & Stability

- [ ] Review environment variable handling and validation
- [ ] Add request rate limiting for web endpoints
- [ ] Add circuit breakers for external API calls
- [ ] Add startup timeout protection
- [ ] Add startup health checks

### Performance

- [ ] Implement connection pooling for HTTP requests
- [ ] Optimize cache expiration strategies
- [ ] Implement batching for Discord notifications
- [ ] Add cache consistency validation
- [ ] Implement cache warming strategy
- [ ] Add cache performance monitoring
- [ ] Add telemetry for performance monitoring

### Data Integrity

- [ ] Add input validation for critical fields in MapSystem module
- [ ] Enhance error handling with proper return types
- [ ] Add data normalization for names and tickers
- [ ] Implement safe creation with error recovery
- [ ] Add missing typespecs in core modules
- [ ] Enhance validation with more specific checks

## High Priority

### Technical Debt

- [ ] Remove backwards compatibility layer in NotifierBehaviour
  - [ ] Audit usages of old non-namespaced module
  - [ ] Remove proxy module if migration is complete
  - [ ] Update documentation to reflect current namespace
- [ ] Replace deprecated API calls in discord/notifier.ex
- [ ] Consolidate duplicate code in notification formatters
- [ ] Refactor config.ex to use proper configuration patterns
- [ ] Clean up unused variables and functions
- [ ] Standardize cache key formats

### Testing & Quality

- [ ] Increase unit test coverage across core functionality
- [ ] Add test suites for edge cases
- [ ] Add benchmarks for critical functions
- [ ] Document test environment setup
- [ ] Review test timeouts and consider making configurable
- [ ] Standardize feature flag testing approach


## Medium Priority

### Architecture Improvements

- [ ] Split Application.ex into smaller modules:
  - [ ] Create StartupPhases module
  - [ ] Create DatabaseManager module
  - [ ] Create CacheManager module
  - [ ] Create WatcherSupervisor module
- [ ] Splitting large modules (MapSystem, Character)
- [ ] Implement data versioning
- [ ] Add audit logging
- [ ] Review database schema design
- [ ] Remove duplicate code from schedulers, ensure each is registered and provides a status for reporting


### Version Management

- [ ] Add `git_ops` for semantic versioning
  - [ ] Add dependency to `mix.exs`
  - [ ] Configure for automated CHANGELOG generation
  - [ ] Set up commit message conventions
- [ ] Create a `VERSION` file at project root
- [ ] Automate version bumping based on Git commits
- [ ] Create `.tool-versions` file for version management
- [ ] Update Dockerfile to use environment variables for versions

### Dependencies

- [ ] Migrate from `mock` to `Mox`
  - [ ] Audit current usage of `mock` in tests
  - [ ] Create migration plan for test updates
  - [ ] Update tests to use `Mox` exclusively
  - [ ] Remove `mock` dependency
- [ ] Document reason for `ranch` override in mix.exs

## Low Priority


### Documentation

- [ ] Review existing documentation, and update based on current code
- [ ] Create troubleshooting guide
- [ ] Document all feature flags and their purposes
- [ ] Document all environment variables in README.md

### Feature Enhancements

- [ ] Add support for more notification channels



## Completed Items

_Move items here when finished, maintaining their original hierarchy_

✅ No items completed yet
