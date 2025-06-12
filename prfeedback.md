# Code Review Feedback - Wanderer Notifier

## Overview

This document contains code review feedback for the Wanderer Notifier Elixir/OTP application. The feedback focuses on performance improvements, code consistency, error handling, and architectural concerns.

## Critical Issues

### 🔥 Security & Memory Management

#### Atom Table Exhaustion

- **File**: `lib/wanderer_notifier/map/map_util.ex:126-129`
- **Issue**: `String.to_atom/1` usage can exhaust atom table with user-supplied keys
- **Fix**: Replace with `String.to_existing_atom/1` or implement key whitelist
- **Impact**: Prevents potential DoS attacks

- **File**: `lib/wanderer_notifier/cache/cache_helper.ex:237`
- **Issue**: Direct `String.to_atom` conversion on `log_name`
- **Fix**: Use helper function mapping known strings to predefined atoms

- **File**: `lib/wanderer_notifier/cache/ets_cache.ex:43-45`
- **Issue**: Dynamic atom creation for GenServer names
- **Fix**: Use static atoms or Registry-based process registration

### 💾 Cache Abstraction Layer

#### Inconsistent Cache Access

- **Files**:
  - `lib/wanderer_notifier/notifications/deduplication/cache_impl.ex:6-9`
  - `lib/wanderer_notifier/notifications/killmail_notification.ex:114-115`
- **Issue**: Direct `Cachex` calls bypass the cache abstraction layer
- **Fix**: Use `WandererNotifier.Cache.Adapter` consistently
- **Context**: Maintains testing capabilities with alternative cache implementations

### ⚡ Performance Issues

#### Redundant Function Calls

- **File**: `lib/wanderer_notifier/api/controllers/health_controller.ex:15-16,55-56`
- **Issue**: `TimeUtils.log_timestamp/0` called twice per request
- **Fix**: Store result in variable, reuse for both timestamp values

#### Process Blocking

- **File**: `lib/wanderer_notifier/killmail/redisq_client.ex:525-536`
- **Issue**: `get_system_name/1` makes synchronous ESI calls, blocking GenServer
- **Fix**: Implement async Task-based lookup

### 🚨 Error Handling & Reliability

#### Unsafe Map Operations

- **File**: `lib/wanderer_notifier/killmail/pipeline_worker.ex:144-147`
- **Issue**: `Map.update!/3` crashes on missing keys
- **Fix**: Use `Map.update/3` with default value of 0

#### Incorrect Uptime Calculation

- **File**: `lib/wanderer_notifier/api/controllers/health_controller.ex:32-34`
- **Issue**: `:erlang.statistics(:wall_clock)` returns 0 on first call
- **Fix**: Use `:erlang.system_info(:uptime)` for reliable system uptime

#### TTL Handling

- **File**: `lib/wanderer_notifier/cache/adapter.ex:44-47`
- **Issue**: `:timer.seconds/1` called on `:infinity` causes ArgumentError
- **Fix**: Add guard clause to handle `:infinity` directly

## Configuration & Infrastructure

### 🐳 Docker Issues

- **File**: `Dockerfile:66-82`
- **Issue**: libc mismatch between Debian build stage and Alpine runtime
- **Fix**: Use consistent libc across both stages

- **File**: `Dockerfile:76-82`
- **Issue**: Hard-pinned package versions cause build failures
- **Fix**: Use version constraints like `~=` for patch updates

### ⚙️ Configuration Management

- **File**: `config/test.exs:54-57`
- **Issue**: Split configuration blocks reduce maintainability
- **Fix**: Consolidate `:wanderer_notifier` config into single block

### 🔧 Environment Handling

- **File**: `lib/wanderer_notifier/config/provider.ex:88-91`
- **Issue**: Default port only applied for nil, not invalid strings
- **Fix**: Explicitly check for nil after parsing

- **File**: `lib/wanderer_notifier/config/system_env_provider.ex:19-23`
- **Issue**: Generic `ArgumentError` for missing environment variables
- **Fix**: Use `KeyError` with specific missing key information

## Code Quality & Consistency

### 📝 Data Structure Consistency

- **File**: `lib/wanderer_notifier/notifications/killmail_notification.ex:348-352`
- **Issue**: Mixed string/atom keys in maps
- **Fix**: Use atom keys (`:id`) consistently

### 🔄 Code Duplication

- **File**: `lib/wanderer_notifier/killmail/zkill_client.ex:65-72`
- **Issue**: Duplicated HTTP request logic
- **Fix**: Delegate to existing `perform_request/1` function

### 📋 Type Specifications

- **File**: `lib/wanderer_notifier/http/utils/rate_limiter.ex:18-25`
- **Issue**: Missing `async: boolean()` in `rate_limit_opts` type
- **Fix**: Add missing option to prevent Dialyzer warnings

### 🏗️ HTTP Response Handling

- **File**: `lib/wanderer_notifier/http.ex:101-110`
- **Issue**: Returns `{:ok, ...}` for all status codes, including errors
- **Fix**: Return `{:error, {:http_error, status}}` for status >= 400

## Build & CI/CD

### 🏃 GitHub Actions

- **File**: `.github/workflows/ci-cd.yml:239-242`
- **Issue**: Deprecated `softprops/action-gh-release@v1`
- **Fix**: Update to `@v2`

### 📦 Mix Configuration

- **File**: `mix.exs:93-102`
- **Issue**: Duplicate `aliases/0` function causes dead code
- **Fix**: Remove duplicate or inlinfinitions

## Logging & Observability

### 📊 Duplicate Logging

- **File**: `lib/wanderer_notifier/notifications/formatters/system.ex:38-48`
- **Issue**: Same exception logged twice
- **Fix**: Keep only structured logger call

### 📈 Missing Telemetry

- **File**: `lib/wanderer_notifier/killmail/pipeline.ex:67-69`
- **Issue**: Duplicate events not logged/telemetered
- **Fix**: Add consistent logging/telemetry for duplicates

## Testing & Maintainability

### 🧪 Cache Configuration

- **File**: `lib/wanderer_notifier/killmail/cache.ex:185`
- **Issue**: Hard-coded `max_recent_kills` value
- **Fix**: Use application configuration with `Application.get_env/3`

### 🎯 Cache TTL

- **File**: `lib/wanderer_notifier/cache/cache_helper.ex:253-257`
- **Issue**: Infinite cache entries without TTL
- **Fix**: Add TTL parameter to cache operations

---

## Implementation Priority

1. **Critical Security Issues** - Atom exhaustion vulnerabilities
2. **Cache Abstraction** - Consistent cache layer usage
3. **Process Reliability** - GenServer blocking and crash prevention
4. **Configuration** - Docker and environment handling
5. **Code Quality** - Consistency and duplication cleanup

---

## Implementation Progress

### ✅ Completed (18/38 items)

#### High Priority
1. **Atom exhaustion fixes** - All 3 critical security issues resolved
   - `map_util.ex` - Now uses `String.to_existing_atom` with error handling
   - `cache_helper.ex` - Added `log_name_to_cache_type` helper function
   - `ets_cache.ex` - Uses Registry for process naming instead of dynamic atoms
   
2. **Cache abstraction layer** - All cache access now goes through adapter
   - `deduplication/cache_impl.ex` - Migrated from direct Cachex calls
   - `killmail_notification.ex` - All 3 Cachex calls replaced with Adapter

3. **Process reliability** 
   - `redisq_client.ex` - ESI calls now async with persistent_term caching
   - `pipeline_worker.ex` - Fixed Map.update! crash risk and Task DOWN handling

#### Medium Priority
4. **Health monitoring**
   - Fixed incorrect uptime calculation using `:erlang.system_info(:uptime)`
   - Note: Timestamp calls were not redundant (different endpoints)

5. **Infrastructure**
   - Fixed Docker libc mismatch (Debian → Debian consistency)
   - Fixed TTL handling for `:infinity` in cache adapter
   - Fixed port parsing to handle invalid strings in config

6. **Code consistency**
   - Fixed string/atom key consistency in `killmail_notification.ex`
   - Fixed HTTP error handling to return errors for status >= 400

### 🚧 In Progress
- **Cache key inconsistency** in `cache_key.ex` - Analyzing `kill/1` vs `killmail/2` usage

### 📋 Remaining (20 items)
- 8 medium priority items (rate limiter, pipeline error handling, etc.)
- 12 low priority items (logging, CI/CD updates, etc.)
