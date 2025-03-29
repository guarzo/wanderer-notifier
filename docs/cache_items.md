### Phase 1: Audit Cache Keys
- [ ] Document current key patterns
  - [ ] List all cache key formats
  - [ ] Map key usage by module
  - [ ] Identify inconsistencies
- [ ] Create key format specification
  - [ ] Define naming conventions
  - [ ] Define separator usage
  - [ ] Define type indicators

### Phase 2: Create Cache Key Module
- [ ] Implement `WandererNotifier.Cache.Keys`
  - [ ] Add key generation functions
  - [ ] Add validation functions
  - [ ] Add documentation
- [ ] Create helper functions
  - [ ] Add type-specific generators
  - [ ] Add validation helpers
  - [ ] Add migration helpers

### Phase 3: Migration
- [ ] Update cache repository
  - [ ] Use new key module
  - [ ] Add key validation
  - [ ] Update tests
- [ ] Update cache usage
  - [ ] Update character cache keys
  - [ ] Update system cache keys
  - [ ] Update killmail cache keys