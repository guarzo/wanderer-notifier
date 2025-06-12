# Code Review Tasks

## 1 — Configuration & Dependency Injection

- [x] **Consolidate configuration reads into WandererNotifier.Config** ✅ Completed
  - **AI Prompt**: "In the Wanderer Notifier codebase, consolidate all configuration reads into WandererNotifier.Config; remove every direct System.get_env/1 call inside business modules by introducing an EnvProvider behaviour that is injected (Mox‑friendly). Update tests accordingly."
  - **Context**: Currently, System.get_env calls are already isolated to configuration modules (`config/config.ex`, `config/provider.ex`). However, there's no EnvProvider behaviour for better testability. The configuration is accessed via `WandererNotifier.Config` module which provides typed accessors.
  - **Completed**: 
    - Created `WandererNotifier.Config.EnvProvider` behaviour
    - Created `WandererNotifier.Config.SystemEnvProvider` implementation
    - Created `WandererNotifier.Config.EnvProviderMock` for testing
    - Updated `WandererNotifier.Config` to use injected provider
    - Updated `config/test.exs` to use mock provider

- [x] **Normalize feature flag structure** ✅ Completed
  - **AI Prompt**: "Normalize the features structure: when the app boots, coerce whatever comes from runtime.exs into a single Keyword list and expose a pure feature_enabled?/1 helper; delete open‑coded pattern matches on raw maps or lists."
  - **Context**: Feature flags are currently stored as a map under `:features` config with individual boolean accessor functions in `lib/wanderer_notifier/config/config.ex` (lines 208-253). These include notifications_enabled?, kill_notifications_enabled?, system_notifications_enabled?, etc.
  - **Completed**: 
    - Added `@default_features` keyword list with all feature defaults
    - Updated `features/0` to normalize config to keyword list and merge with defaults
    - All feature-specific functions now use unified `feature_enabled?/1`
    - Added documentation for `feature_enabled?/1` as primary interface

## 2 — OTP Supervision & Module Boundaries

- [ ] **Create explicit contexts and reorganize supervision tree**
  - **AI Prompt**: "Create explicit contexts (Notifier.Killmail, Notifier.ExternalAdapters, etc.). Move all HTTP/Discord, Cachex and RedisQ processes out of domain files and register them under WandererNotifier.Application so that the supervision tree is declared in one place."
  - **Context**: Current supervision tree in `lib/wanderer_notifier/application.ex` includes:
    - Base children: NoopConsumer, Cachex, TaskSupervisor, Stats, License.Service, Application.Service, Web.Server
    - Conditional: Killmail.Supervisor (if RedisQ enabled), Schedulers.Supervisor
  - **Issues**: HTTP clients and Discord notifiers are not explicitly supervised; they're called directly from domain modules
  - **Target structure**:
    - `Notifier.Killmail` context for killmail processing
    - `Notifier.ExternalAdapters` for HTTP/Discord/Redis clients
    - All processes registered under main Application supervisor

- [ ] **Convert Task.start to supervised processes**
  - **AI Prompt**: "Scan the project for Task.start/1 or hidden worker spawns; convert them to named GenServers or DynamicSupervisors so that runtime restarts are visible to ops."
  - **Context**: Found Task.Supervisor usage in `lib/wanderer_notifier/application.ex` but need to verify if there are any Task.start/1 calls in business logic
  - **Known supervisors**: 
    - `WandererNotifier.TaskSupervisor` - Generic task supervisor
    - `WandererNotifier.Schedulers.Supervisor` - Manages background schedulers
    - `WandererNotifier.Killmail.Supervisor` - Manages killmail pipeline

## 3 — Error Handling & Observability

- [x] **Add structured metadata to Logger calls** ✅ Completed
  - **AI Prompt**: "Replace bare Logger.warning/1 calls with Logger.warning/2 that includes structured metadata (:character_id, :system_id, etc.). Provide a helper macro to avoid repetition."
  - **Context**: The codebase has dedicated error logging modules:
    - `lib/wanderer_notifier/logger/error_logger.ex` - Provides structured error logging functions
    - `lib/wanderer_notifier/logger/logger.ex` - Main logger module with helper functions
    - `lib/wanderer_notifier/logger/metadata_keys.ex` - Defines metadata keys
  - **Completed**:
    - Created `WandererNotifier.Logger.StructuredLogger` with helper macros
    - Macros automatically extract metadata from common structures (killmails, characters, systems)
    - Provides `log_info`, `log_debug`, `log_warn`, `log_error` macros
    - Existing logger already has excellent structured metadata support
    - All category-specific helpers (api_*, cache_*, etc.) use structured metadata

## 4 — Caching Layer Improvements

- [ ] **Introduce lightweight ETS cache for tests**
  - **AI Prompt**: "Introduce a lightweight ETS cache implementing CacheBehaviour for unit tests; inject it via Application.compile_env/3 so production keeps Cachex while tests stay pure Erlang."
  - **Context**: 
    - Current cache behaviour: `lib/wanderer_notifier/cache/cache_behaviour.ex`
    - Production uses Cachex (configured in `application.ex`)
    - Tests use `:wanderer_test_cache` with Cachex
    - Cache helper: `lib/wanderer_notifier/cache/cache_helper.ex` provides high-level abstraction
  - **Benefits**: Faster tests, no external dependencies in test environment

- [ ] **Centralize TTL values**
  - **AI Prompt**: "Centralise TTL values: enforce callers to use Cache.Config.ttl_for/1 rather than literal integers. Add a Credo custom check that flags hard‑coded TTL seconds."
  - **Context**: 
    - TTL configuration exists in `lib/wanderer_notifier/cache/config.ex`
    - Current TTLs: Character/corp/alliance (24h), System info (1h), Deduplication (30m)
    - Some modules may still have hardcoded TTL values
  - **Target**: All TTL values accessed via `Cache.Config.ttl_for(:cache_type)`

## 5 — Test Suite Hardening

- [ ] **Refactor tests to use ETS adapter**
  - **AI Prompt**: "Refactor tests to remove external Cachex dependency: default to the new ETS adapter; convert existing Mox stubs to use with_cache/4 helpers."
  - **Context**: 
    - Test configuration in `config/test.exs` currently uses Cachex
    - Test helpers in `test/support/` directory
    - Mox is used for mocking behaviors
  - **Dependencies**: Requires ETS cache implementation from task 4.1

- [ ] **Add property-based tests**
  - **AI Prompt**: "Add property‑based tests with StreamData for: — KeyGenerator.parse_key/1 (round‑trip) — killmail JSON encoder/decoder invariants."
  - **Context**: 
    - KeyGenerator in `lib/wanderer_notifier/cache/key_generator.ex`
    - Killmail schema in `lib/wanderer_notifier/killmail/schema.ex`
    - No StreamData dependency currently in `mix.exs`
  - **Target areas**: Cache key generation, JSON serialization/deserialization

## 6 — Idiomatic Elixir Clean-ups

- [ ] **Remove pass-through private functions**
  - **AI Prompt**: "Find all private functions that are mere pass‑throughs (e.g., Config.map_api_url/0 → Config.map_url/0); inline them and mark old names @deprecated."
  - **Context**: Common in configuration modules where private functions just call other functions
  - **Example locations**: 
    - `lib/wanderer_notifier/config/config.ex`
    - Various client modules that wrap API calls
  - **Pattern**: `defp foo(), do: bar()` → inline `bar()` directly

- [ ] **Standardize integer parsing**
  - **AI Prompt**: "Use guards + Integer.parse/1 || default helper (parse_int/2) everywhere; eliminate bespoke case Integer.parse patterns."
  - **Context**: 
    - Parsing utilities in `lib/wanderer_notifier/config/utils.ex`
    - Multiple modules may have custom integer parsing logic
  - **Target**: Single `parse_int/2` helper used consistently

## 8 — Docker & Release Optimisation

- [ ] **Optimize Docker image size**
  - **AI Prompt**: "Convert the current single‑stage Dockerfile to a two‑stage build (builder on hexpm/elixir, final on alpine:3.20); strip build tools, verify the image shrinks below 60 MB."
  - **Context**: 
    - Current Dockerfile already uses multi-stage build (deps → build → runtime)
    - Uses Elixir 1.18.3 with OTP 27
    - Has cache mounts for faster rebuilds
  - **Optimization opportunities**: 
    - Switch runtime stage to Alpine Linux
    - Remove unnecessary build artifacts
    - Minimize installed packages

## 10 — Quick-Win Refactors

- [ ] **Introduce CacheKey struct**
  - **AI Prompt**: "Introduce %CacheKey{} struct that implements String.Chars; migrate existing tuple keys in Cachex calls to the struct to gain Dialyzer coverage."
  - **Context**: 
    - Current cache keys are generated as strings in `lib/wanderer_notifier/cache/key_generator.ex`
    - Key patterns defined in `lib/wanderer_notifier/cache/keys.ex`
  - **Benefits**: Type safety, better documentation, Dialyzer coverage

- [ ] **Add response compression**
  - **AI Prompt**: "Add Plug.Gzip (compress: true) to the main API pipeline to gzip JSON responses automatically; update benchmark to confirm ~70% reduction in wire size."
  - **Context**: 
    - Web router in `lib/wanderer_notifier/web/router.ex`
    - API endpoints serve JSON responses
    - No compression currently configured
  - **Implementation**: Add to plug pipeline in router