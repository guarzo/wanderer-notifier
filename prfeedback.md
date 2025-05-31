# PR Feedback - Issues to Address

## Scheduler and Configuration Issues

- [x] **BaseScheduler: Make get_scheduler_interval more generic**

  - **File:** `lib/wanderer_notifier/schedulers/base_scheduler.ex` (lines 66-81)
  - **Issue:** Function uses hardcoded module names which limits reusability
  - **Fix:** Define a callback `interval_key()` in the behavior that returns the config key as an atom. Refactor `get_scheduler_interval` to call `interval_key()`, retrieve the default interval from opts, and fetch the config value using `Application.get_env` with the returned key and default.

- [x] **BaseScheduler: Remove hardcoded module names in update_stats_count**
  - **File:** `lib/wanderer_notifier/schedulers/base_scheduler.ex` (lines 278-289)
  - **Issue:** Function uses hardcoded module names and a nested module without aliasing
  - **Fix:** Add `alias WandererNotifier.Core.Stats` at the top of the module, define a `@callback stats_type() :: atom() | nil`, and refactor `update_stats_count` to call `stats_type()` instead of pattern matching on the module argument, then call `Stats.set_tracked_count` with the returned atom if not nil.

## Alias and Import Issues

- [x] **MapClient: Fix alias ordering and Logger alias**

  - **File:** `lib/wanderer_notifier/map/clients/client.ex` (lines 9-10)
  - **Issue:** Alias statements not alphabetical and Logger alias uses `:as` option
  - **Fix:** Reorder alias statements alphabetically and remove the `:as` option from the Logger alias. Change to `alias WandererNotifier.Logger.Logger`. Update all references from `AppLogger` to `Logger`.

- [x] **MapCharacter: Remove :as option from Keys alias**

  - **File:** `lib/wanderer_notifier/map/map_character.ex` (line 34)
  - **Issue:** Alias uses `:as` option
  - **Fix:** Remove the `:as` option so it reads `alias WandererNotifier.Cache.Keys`. Update all references from `CacheKeys` to `Keys`.

- [x] **NeoClient: Simplify Nostrum.Api.Message call**

  - **File:** `lib/wanderer_notifier/notifications/neo_client.ex` (line 11)
  - **Issue:** Using full module path instead of alias
  - **Fix:** Add `alias Nostrum.Api.Message` near module declarations, then update the call to use `Message.create`.

- [x] **SystemDeterminer: Add Cachex alias**

  - **File:** `lib/wanderer_notifier/notifications/determiner/system.ex` (lines 48, 51, 82, 85)
  - **Issue:** Cachex called directly without alias
  - **Fix:** Add alias for Cachex at the top of the module. Replace all direct calls like `Cachex.get/2` with the aliased version.

- [x] **HealthController: Remove redundant import**

  - **File:** `lib/wanderer_notifier/api/controllers/health_controller.ex` (line 7)
  - **Issue:** Redundant import of `WandererNotifier.Api.Helpers`
  - **Fix:** Remove the explicit import as it's already imported via `WandererNotifier.Api.Controllers.ControllerHelpers`.

- [x] **HealthController: Remove :as option from alias**

  - **File:** `lib/wanderer_notifier/api/controllers/health_controller.ex` (line 9)
  - **Issue:** Alias uses `:as` option
  - **Fix:** Remove the `:as` option and alias the module directly. Update all references (including line 27).

- [x] **CommonFormatter: Remove :as options from aliases**

  - **File:** `lib/wanderer_notifier/notifications/formatters/common.ex` (lines 9-10)
  - **Issue:** Alias declarations use `:as` option
  - **Fix:** Remove `:as` options for CharacterFormatter and SystemFormatter. Update all calls to use fully qualified module names.

- [x] **SystemFormatter: Fix aliases and references**
  - **File:** `lib/wanderer_notifier/notifications/formatters/system.ex` (lines 7-9)
  - **Issue:** Alias uses `:as` option and incorrect ordering
  - **Fix:** Remove `:as` option from `WandererNotifier.Logger.Logger` alias, reorder aliases alphabetically (MapSystem before Enrichment), replace `AppLogger` references with full module name.

## Type and Data Issues

- [x] **Character ID Type Consistency**

  - **Files:** Multiple files across the codebase
  - **Issue:** Breaking mismatches between typespecs, implementation and tests due to character_id switching from String.t() to integer()
  - **Action:** Choose canonical type (string or integer), update callers, adjust typespecs, fix tests
  - **Impacted areas:**
    - `lib/wanderer_notifier/map/map_character.ex`
    - Multiple test files
    - Formatter modules
    - URL-builder modules

- [x] **CacheImpl: Add type guards**

  - **File:** `lib/wanderer_notifier/notifications/deduplication/cache_impl.ex` (lines 9-29)
  - **Issue:** Functions `check/2` and `clear_key/2` lack type guards
  - **Fix:** Reintroduce type guards to ensure type is an atom and id is either an integer or binary.

- [x] **SystemStaticInfo: Refactor explicit try block**

  - **File:** `lib/wanderer_notifier/map/system_static_info.ex` (line 167)
  - **Issue:** Explicit try block should use implicit try pattern
  - **Fix:** Replace with `with` statement pipeline that handles errors gracefully.

- [x] **SystemStaticInfo: Fix string key access**
  - **File:** `lib/wanderer_notifier/map/system_static_info.ex` (line 169)
  - **Issue:** Accesses `solar_system_id` using string keys, can break with atom-keyed structs
  - **Fix:** Create helper function `get_system_id/1` that pattern matches both MapSystem structs and maps with string keys.

## Documentation and Formatting

- [x] **Index.md: Fix blockquote formatting**

  - **File:** `index.md` (lines 104-106)
  - **Issue:** Blank line inside blockquote violates markdown formatting rules
  - **Fix:** Remove blank line within blockquote for continuous text.

- [x] **README.md: Format bare URLs**

  - **File:** `README.md` (lines 136-191)
  - **Issue:** Bare URLs flagged by static analysis
  - **Fix:** Replace bare URLs with properly formatted markdown links `[text](url)`.

- [x] **Spelling consistency: Use British English "behaviour"**
  - **Files:** `test/support/test_cache_stubs.ex` (line 3), documentation files
  - **Issue:** Inconsistent spelling of "behavior" vs "behaviour"
  - **Fix:** Update all documentation to use "behaviour" consistently across `notifications.md`, `SCHEDULER_NOTIFICATIONS.md`, and `lib/wanderer_notifier/killmail/redisq_client.ex`.
