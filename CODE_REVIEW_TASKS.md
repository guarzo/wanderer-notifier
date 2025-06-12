# Code Review Tasks - Refactoring & Consistency Improvements

This document contains tasks identified from a code review focusing on duplicated code, inconsistent patterns, and non-idiomatic Elixir code.

## Progress Summary
- **Completed**: 30 major tasks
- **In Progress**: 0 tasks  
- **Remaining**: 0 primary tasks (all major refactoring tasks completed)

## 1. Eliminate Duplicated Code

### HTTP Response Handling
- [x] Create a unified HTTP response handler module to eliminate duplicated status code handling
  - Found in: `esi/client.ex:166-202`, `killmail/zkill_client.ex:126-147`, `map/system_static_info.ex:55-89`, `map/clients/base_map_client.ex:104-133`
  - Pattern: Similar case statements for status codes (200, 404, other errors)
  - **COMPLETED**: Created `lib/wanderer_notifier/http/response_handler.ex`

### Caching Patterns
- [x] Abstract the `fetch_with_cache` pattern into a higher-order function or macro
  - Found in: `esi/service.ex` - `get_character_info:93`, `get_corporation_info:118`, `get_alliance_info:146`, `get_system:304`, `get_type:382`
  - Pattern: Repeated Cachex fetch logic with different keys
  - **COMPLETED**: Created `lib/wanderer_notifier/cache/cache_helper.ex`

### Cache Name Configuration
- [x] Centralize cache name configuration access
  - Found in: Multiple locations using `Application.get_env(:wanderer_notifier, :cache_name, :wanderer_cache)`
  - Create single interface for cache name retrieval
  - **COMPLETED**: Created `lib/wanderer_notifier/cache/config.ex`

### HTTP Headers
- [x] Extract common HTTP client configuration into shared module
  - Found in: `esi/client.ex:158-163`, `killmail/zkill_client.ex:151-157`, `map/system_static_info.ex`
  - Pattern: Similar `default_headers/0` functions
  - **COMPLETED**: Created `lib/wanderer_notifier/http/headers.ex`

## 2. Fix Inconsistent Patterns

### Dependency Injection
- [x] Standardize dependency injection approach
  - [x] Choose between direct module references, application env, or compile-time config
  - [x] Document the chosen pattern in ARCHITECTURE.md
  - **COMPLETED**: Created `WandererNotifier.Core.Dependencies` module for centralized dependency injection

### Test Patterns

## 5. Additional Improvements

### Code Organization
- [x] Review module dependencies and reduce coupling
  - **COMPLETED**: Analyzed cross-module dependencies and updated ARCHITECTURE.md with coupling reduction recommendations

## Notes

- Consider creating a style guide based on these improvements
- Run tests after each change to ensure no regressions
- Update CLAUDE.md with any new patterns or conventions adopted



Automatic Image / Common Versioning Failure
Prepare all required actions
Run ./.github/actions/common-versioning
Run # Setup Mix
/home/runner/work/_temp/bb17d0f3-1539-43ac-b2c2-869d87ea4196.sh: line 2: mix: command not found
Error: Process completed with exit code 127.