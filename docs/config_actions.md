### Phase 1: Configuration Analysis
- [ ] Audit current configuration usage
  - [ ] Map all `Application.get_env` calls in the codebase
  - [ ] Identify hardcoded values in config files
  - [ ] Document which configs are runtime vs compile-time
  - [ ] List all environment variables used

### Phase 2: Create Domain-Specific Configuration Modules
- [ ] Create `WandererNotifier.Config.API`
  - [ ] Move ESI API configuration
  - [ ] Move ZKillboard API configuration
  - [ ] Add validation functions for API settings
- [ ] Create `WandererNotifier.Config.Notifications`
  - [ ] Move Discord configuration
  - [ ] Move notification channel settings
  - [ ] Add notification feature flag handling
- [ ] Create `WandererNotifier.Config.Cache`
  - [ ] Move cache settings and TTLs
  - [ ] Add cache validation functions
- [ ] Create `WandererNotifier.Config.Features`
  - [ ] Consolidate feature flag handling
  - [ ] Add feature validation functions

### Phase 3: Move Validation from runtime.exs
- [ ] Move MAP_URL_WITH_NAME validation to application code
  - [ ] Create validation module in `WandererNotifier.Config.Validation`
  - [ ] Add validation to application startup
  - [ ] Add clear error messages for invalid configurations
- [ ] Move other validations from runtime.exs
  - [ ] Discord token validation
  - [ ] Database configuration validation
  - [ ] Feature flag validation

### Phase 4: Update Code References
- [ ] Update all modules to use new configuration modules
- [ ] Add typespecs and documentation
- [ ] Update tests to use new configuration structure
- [ ] Remove direct `Application.get_env` calls