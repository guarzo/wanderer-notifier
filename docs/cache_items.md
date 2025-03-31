### Phase 1: Audit Cache Keys ✅

- [x] Document current key patterns
  - [x] List all cache key formats
  - [x] Map key usage by module
  - [x] Identify inconsistencies
- [x] Create key format specification
  - [x] Define naming conventions
  - [x] Define separator usage
  - [x] Define type indicators

### Phase 2: Create Cache Key Module ✅

- [x] Implement `WandererNotifier.Cache.Keys`
  - [x] Add key generation functions
  - [x] Add validation functions
  - [x] Add documentation
- [x] Create helper functions
  - [x] Add type-specific generators
  - [x] Add validation helpers
  - [x] Add migration helpers

### Phase 3: Migration ✅

- [x] Update cache repository
  - [x] Use new key module
  - [x] Add key validation
  - [x] Update tests
- [x] Update cache usage
  - [x] Update notifiers/determiner.ex
  - [x] Update processing/killmail/comparison.ex
  - [x] Update processing/killmail/cache.ex
  - [x] Update api_controller.ex
  - [x] Update resources/killmail_persistence.ex
  - [x] Update resources/tracked_character.ex
  - [x] Update api/map/systems_client.ex
  - [x] Update schedulers/character_update_scheduler.ex

### Phase 4: Validation & Cleanup ⏳

- [x] Fix compilation errors
- [ ] Address remaining warnings
- [ ] Add linter rules for cache key usage
- [ ] Verify all cache keys are standardized
- [ ] Create documentation for cache key patterns
- [ ] Performance testing

### Benefits Achieved ✅

- Consistent cache key format across the application
- Centralized cache key generation to prevent typos and inconsistencies
- Better type validation and error handling
- Improved maintainability for cache operations
- Enhanced debugging capabilities with standardized key patterns
- Code successfully compiles with the new cache key module

### Usage Examples

```elixir
alias WandererNotifier.Cache.Keys, as: CacheKeys

# Generate a key for system data
system_key = CacheKeys.system(30004759)  # "map:system:30004759"

# Generate a key for tracked character
character_key = CacheKeys.tracked_character(12345)  # "tracked:character:12345"

# Generate a key for ESI killmail data
killmail_key = CacheKeys.esi_killmail(98765)  # "esi:killmail:98765"

# Check if a key is valid
CacheKeys.valid?("map:system:12345")  # true
CacheKeys.valid?("invalid-key")  # false

# Determine key type
CacheKeys.is_array_key?("recent:kills")  # true
CacheKeys.is_map_key?("map:system:12345")  # true
```

### Known Issues

There are some remaining warnings in the code that should be addressed in a future cleanup phase:

1. Some unused functions and variables
2. Some undefined or private functions that are referenced
3. Some missing module aliases

These issues don't affect the functionality of the cache key standardization but should be cleaned up for code quality.
