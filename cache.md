## Phase 1: Inventory & Audit

✅ **Completed: Locate all literal cache-key usages**

- Searched the entire codebase for literal cache key patterns
- Found that the codebase is already following best practices with centralized cache key management
- No literal cache key strings found in the codebase

✅ **Completed: Classify each usage**

- All cache keys are already properly classified and managed through `WandererNotifier.Cache.Keys`
- Key format follows the recommended pattern: `prefix:entity_type:id`
- Helper functions exist for all major entity types

## Phase 2: Refactoring Core Modules

✅ **Completed: Consolidate remaining string interpolations**

1. **Moved string interpolations to Cache.Keys**
   - Added new helper functions:
     ```elixir
     def zkill_recent_kill(kill_id), do: combine([@prefix_zkill, "recent_kills"], [kill_id], nil)
     def dedup_system(id), do: combine([@prefix_dedup, @entity_system], [id], nil)
     def dedup_character(id), do: combine([@prefix_dedup, @entity_character], [id], nil)
     def dedup_kill(id), do: combine([@prefix_dedup, @entity_killmail], [id], nil)
     ```
   - Updated `killmail/cache.ex` to use `zkill_recent_kill/1`
   - Updated `Deduplication.CacheImpl` to use deduplication helpers

## Phase 3: Update Tests & Mocks

✅ **Completed: Test fixtures**

- All test fixtures already use `Cache.Keys` helpers
- No literal cache key strings found in tests

## Phase 4: CI & Linting

✅ **Completed: Add CI checks**

1. **Added Credo check**

   - Created custom check `Credo.Check.Warning.CacheKeyStringLiteral`
   - Added to `.credo.exs` configuration
   - Check warns about string literals matching cache key patterns

2. **Added pre-commit hook**

   - Created `.git/hooks/pre-commit` script
   - Checks staged files for cache key patterns
   - Provides helpful error message with examples

## Phase 5: Documentation & Onboarding

✅ **Completed: Documentation**

- `Cache.Keys` module is well documented
- Each helper function has clear documentation
- Key format is documented in module docs

## Phase 6: Continuous Enforcement

✅ **Completed: Add enforcement**

1. **Code Review Checklist**

   - Added "🔑 No raw cache-key strings" to PR template
   - Added link to `Cache.Keys` module documentation
   - Added cache key guidelines section

2. **Pre-commit hook**

   - Added check for cache key patterns
   - Warns on any string literals matching the pattern

3. **Periodic Audit**
   - Set up quarterly scan for cache key patterns
   - Created automated issue for any findings

---

Summary of Changes:

1. Added new helper functions to `Cache.Keys` for zkill and deduplication keys
2. Updated modules to use the new helper functions
3. Created custom Credo check for cache key patterns
4. Added pre-commit hook to prevent new cache key literals
5. Updated PR template with cache key guidelines

The codebase is now fully compliant with the cache key management guidelines. All cache keys are generated through the `Cache.Keys` module, and there are multiple safeguards in place to prevent the introduction of literal cache key strings.
