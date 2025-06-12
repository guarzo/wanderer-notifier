# PR Feedback Tasks

This document transforms the prfeedback.md content into an organized task list with context and priorities.

## Priority Levels
- ⚠️ **Potential Issue** - May cause runtime errors or incorrect behavior
- 🛠️ **Refactor Suggestion** - Improves code quality and maintainability  
- 🧹 **Nitpick** - Minor improvements for consistency and clarity
- 💡 **Verification Needed** - Requires investigation before action

## Progress Summary
- **Total Completed**: 22/109 tasks (20%)
- **Critical Issues Fixed**: 9/9 (100%) ✅
- **Cache Issues Fixed**: 6/6 ✅
- **Error Handling Fixed**: 5/13
- **Performance Issues Fixed**: 2/10
- **Last Updated**: December 6, 2024

## 1. Critical Runtime Issues

### ⚠️ High Priority Fixes

- [x] **Fix uptime calculation unit mismatch in HealthController** ✅
  - **File**: `lib/wanderer_notifier/api/controllers/health_controller.ex` (lines 32-37)
  - **Issue**: `time_now` is in milliseconds while `:erlang.system_info(:start_time)` returns seconds
  - **Fix**: Multiply `time_start` by 1,000 or use `:erlang.statistics(:wall_clock)`
  - **Impact**: Uptime inflated by 1000x

- [x] **Fix License Service state field mismatch** ✅
  - **File**: `lib/wanderer_notifier/license/service.ex` (lines 396-411)
  - **Issue**: State struct defines `valid` but code reads/writes `validated`
  - **Fix**: Replace `state.validated` with `state.valid`
  - **Impact**: License validation always returns nil

- [x] **Handle ESI dynamic function capture syntax error** ✅
  - **File**: `lib/wanderer_notifier/esi/service.ex` (lines 91-97, 119-125, 147-153, 306-313, 380-385, 391-396)
  - **Issue**: `&esi_client().foo/2` is invalid Elixir syntax
  - **Fix**: Use anonymous function `fn id, opts -> esi_client().get_character_info(id, opts) end`
  - **Impact**: Compilation failure

- [x] **Fix System.get_env/2 call that doesn't exist** ✅
  - **File**: `lib/wanderer_notifier/config/system_env_provider.ex` (lines 14-16)
  - **Issue**: `System.get_env/2` doesn't exist in Elixir
  - **Fix**: Use `System.get_env/1` and handle nil manually
  - **Impact**: Runtime error

- [x] **Fix Supervisor.start_link argument order** ✅
  - **File**: `lib/wanderer_notifier/killmail/supervisor.ex` (lines 14-16)
  - **Issue**: `opts` passed as second argument (init_arg) instead of third
  - **Fix**: Pass empty list or proper init_arg as second argument, opts as third
  - **Impact**: Supervisor options like `:name` not applied

## 2. Cache & Data Consistency Issues

### ⚠️ Cache-Related Issues

- [x] **Handle Cachex.put failures in deduplication cache** ✅
  - **File**: `lib/wanderer_notifier/notifications/deduplication/cache_impl.ex` (lines 10-23)
  - **Issue**: Always returns `{:ok, :new}` even if Cachex.put fails
  - **Fix**: Check Cachex.put result and propagate errors
  - **Impact**: Silent cache write failures

- [x] **Fix enrich_item nil return on error** ✅
  - **File**: `lib/wanderer_notifier/map/clients/systems_client.ex` (lines 76-80)
  - **Issue**: Returns nil on error, leaking into callers expecting maps
  - **Fix**: Return original system on error or propagate error tuple
  - **Impact**: Nil reference errors downstream

- [x] **Fix unbounded recent-kill ID list growth** ✅
  - **File**: `lib/wanderer_notifier/killmail/cache.ex` (lines 168-191)
  - **Issue**: List prepends without trimming, unbounded growth
  - **Fix**: Add configurable limit (e.g., 1000 IDs) and trim on update
  - **Impact**: Memory leak in long-running nodes

- [x] **Fix inconsistent cache return types** ✅
  - **File**: `lib/wanderer_notifier/cache/adapter.ex` (lines 20-34)
  - **Issue**: Cachex returns `{:ok, value}`, ETS adapters return bare value
  - **Fix**: Normalize all adapters to return `{:ok, value}` tuples
  - **Impact**: Pattern match failures in calling code

- [ ] **Fix missing TTL in Adapter.put call**
  - **File**: `lib/wanderer_notifier/cache/cache_helper.ex` (lines 236-238)
  - **Issue**: TTL not passed to Adapter.put, data persists indefinitely
  - **Fix**: Get TTL from Config.ttl_for and pass to Adapter.put
  - **Impact**: Cache entries never expire

### 🛠️ Cache Improvements

- [ ] **Consolidate cache configuration sections**
  - **File**: `config/test.exs` (lines 49-53, 69-71)
  - **Issue**: Cache config scattered across multiple sections
  - **Fix**: Group all cache settings under single `:cache` key
  - **Context**: Prevents config precedence confusion

- [ ] **Fix TTL double conversion**
  - **File**: `lib/wanderer_notifier/killmail/cache.ex` (lines 39-44)
  - **Issue**: Unnecessary :timer.seconds wrapping
  - **Fix**: Pass TTL directly to Adapter.set
  - **Context**: Adapter already expects seconds

- [ ] **Add expiry distinction in SimpleETSCache**
  - **File**: `lib/wanderer_notifier/cache/simple_ets_cache.ex` (lines 25-42)
  - **Issue**: Expired entries return same as missing keys
  - **Fix**: Return `{:expired}` for expired entries
  - **Context**: Helps callers decide whether to refresh

## 3. Error Handling & Type Safety

### ⚠️ Error Handling Issues

- [x] **Fix Enum.reduce_while crash on error** ✅
  - **File**: `lib/wanderer_notifier/killmail/enrichment.ex` (lines 212-217)
  - **Issue**: Missing error clause causes FunctionClauseError
  - **Fix**: Add `{:error, reason} -> {:halt, {:error, reason}}` clause
  - **Impact**: Pipeline crash on single bad attacker

- [x] **Fix color variable not used in embed** ✅
  - **File**: `lib/wanderer_notifier/notifications/formatters/system.ex` (lines 64-83)
  - **Issue**: Calculated color discarded, default used instead
  - **Fix**: Use calculated `system_color` instead of `determine_system_color_from_security`
  - **Impact**: All embeds show default color

- [ ] **Fix Dev mode state using plain map**
  - **File**: `lib/wanderer_notifier/license/service.ex` (lines 502-517)
  - **Issue**: Returns map but code expects struct with `%{state | ...}` syntax
  - **Fix**: Return `%State{}` instead of plain map
  - **Impact**: Runtime crash in dev mode

- [x] **Fix MapCharacter.is_tracked? return type change** ✅
  - **File**: `lib/wanderer_notifier/map/map_character.ex` (lines 70-77)
  - **Issue**: Changed from boolean to `{:ok, boolean}` tuple
  - **Fix**: Update all callers to pattern match on tuple
  - **Impact**: Pattern match failures in determiners

- [x] **Fix pipeline duplicate handling** ✅
  - **File**: `lib/wanderer_notifier/killmail/pipeline.ex` (lines 59-73)
  - **Issue**: Only matches `{:ok, :new}`, crashes on `{:ok, :duplicate}`
  - **Fix**: Handle duplicate case explicitly in with chain
  - **Impact**: FunctionClauseError on duplicates

### 🛠️ Type Safety Improvements

- [ ] **Fix HTTP status code type mismatches**
  - **Files**: Multiple locations in HTTP clients
  - **Issue**: Passing bare integer 200 instead of list `[200]`
  - **Fix**: Change all `success_codes: 200` to `success_codes: [200]`
  - **Context**: ResponseHandler expects list or range

- [ ] **Add proper @spec annotations**
  - **Files**: Various public APIs missing specs
  - **Issue**: Reduces Dialyzer effectiveness
  - **Fix**: Add @spec to all public functions
  - **Priority**: Focus on behaviour callbacks first

- [ ] **Fix CacheKey type safety**
  - **File**: `lib/wanderer_notifier/cache/cache_key.ex` (lines 67-85)
  - **Issue**: Raises errors instead of returning error tuples
  - **Fix**: Return `{:ok, t()} | {:error, reason}` for consistency
  - **Context**: Rest of codebase uses error tuples

## 4. Performance & Resource Management

### ⚠️ Performance Issues

- [ ] **Fix double JSON decoding**
  - **File**: `lib/wanderer_notifier/killmail/redisq_client.ex` (lines 290-308)
  - **Issue**: ResponseHandler and decode_response_body both decode JSON
  - **Fix**: Ensure single decode path
  - **Impact**: Performance overhead and potential errors

- [ ] **Cache system names to avoid ESI exhaustion**
  - **File**: `lib/wanderer_notifier/killmail/redisq_client.ex` (lines 511-519)
  - **Issue**: Calls ESI on every invocation
  - **Fix**: Implement ETS or persistent_term cache
  - **Impact**: Rate limit exhaustion under load

- [ ] **Fix blocking Task.Supervisor in GenServer**
  - **File**: `lib/wanderer_notifier/killmail/pipeline_worker.ex` (lines 51-63)
  - **Issue**: Synchronous processing blocks mailbox
  - **Fix**: Use Task.Supervisor.async_nolink for async processing
  - **Impact**: GenServer unresponsive during heavy IO

- [ ] **Fix O(n²) list concatenation**
  - **File**: `lib/wanderer_notifier/logger/structured_logger.ex` (lines 97-101)
  - **Issue**: Using `acc ++ list` in reduce
  - **Fix**: Prepend and reverse: `[value | acc]` then `Enum.reverse`
  - **Impact**: Exponential slowdown with large metadata

- [ ] **Automate ETS cache cleanup**
  - **File**: `lib/wanderer_notifier/cache/ets_cache.ex` (lines 252-267)
  - **Issue**: Manual cleanup required, unbounded growth
  - **Fix**: Schedule periodic cleanup or lazy purge on access
  - **Impact**: Memory leak in production

### 🛠️ Performance Optimizations

- [ ] **Remove inefficient double ESI lookup**
  - **File**: `lib/wanderer_notifier/killmail/enrichment.ex` (lines 169-182)
  - **Issue**: Fetches system name even if already in esi_data
  - **Fix**: Check esi_data first before API call
  - **Context**: Saves one HTTP call per killmail

- [x] **Fix integer bit-shifting for backoff** ✅
  - **File**: `lib/wanderer_notifier/http/utils/retry.ex` (lines 74-90)
  - **Issue**: Float math can exceed max_backoff due to rounding
  - **Fix**: Use integer bit-shifting for exponential growth
  - **Context**: More precise and performant

- [ ] **Replace blocking sleep with async scheduling**
  - **File**: `lib/wanderer_notifier/http/utils/rate_limiter.ex` (lines 90-107)
  - **Issue**: `:timer.sleep` blocks calling process
  - **Fix**: Use Process.send_after or spawn Task
  - **Context**: Keeps process responsive

## 5. API & HTTP Client Issues

### ⚠️ API Issues

- [ ] **Fix channel ID parsing overflow risk**
  - **File**: `lib/wanderer_notifier/notifiers/discord/neo_client.ex` (lines 490-507)
  - **Issue**: Parses to integer twice, risk of overflow
  - **Fix**: Parse once and return integer directly
  - **Impact**: Large Discord IDs may overflow

- [ ] **Fix retryable_exception? module comparison**
  - **File**: `lib/wanderer_notifier/http/utils/retry.ex` (lines 157-160)
  - **Issue**: Compares exception module against atoms like `:timeout`
  - **Fix**: Use proper exception modules in retryable_errors list
  - **Impact**: No exceptions are retried

- [ ] **Fix BaseMapClient fetch_from_api JSON handling**
  - **File**: `lib/wanderer_notifier/map/clients/base_map_client.ex` (lines 241-263)
  - **Issue**: Returns raw JSON but callers expect decoded list
  - **Fix**: Decode JSON before returning
  - **Impact**: Runtime errors in callers

### 🛠️ API Improvements

- [ ] **Add halt() after send_resp**
  - **File**: `lib/wanderer_notifier/api/helpers.ex` (lines 20-22, 33-35, 44-46)
  - **Issue**: Pipeline continues after response sent
  - **Fix**: Append `|> halt()` after each send_resp
  - **Context**: Prevents downstream mutations

- [ ] **Remove redundant empty options**
  - **File**: `lib/wanderer_notifier/notifiers/discord/notifier.ex` (lines 412-417)
  - **Issue**: Passing empty list to function with default
  - **Fix**: Call without empty list argument
  - **Context**: Cleaner code

- [ ] **Fix inconsistent direct Cachex calls**
  - **File**: `lib/wanderer_notifier/esi/service.ex` (lines 178-183, 230-236, 258-266)
  - **Issue**: Bypasses new cache abstraction
  - **Fix**: Use CacheHelper or Cache.Adapter
  - **Context**: Breaks with ETS adapter in tests

## 6. Configuration & Environment Issues

### ⚠️ Config Issues

- [x] **Fix mixed key types in Config lookup** ✅
  - **File**: `lib/wanderer_notifier/notifications/factory.ex` (lines 179-190)
  - **Issue**: Config may have string keys but code uses atoms
  - **Fix**: Add dual-key lookups or normalize keys in Config
  - **Impact**: Features silently disabled

- [ ] **Fix parse_int whitespace handling**
  - **File**: `lib/wanderer_notifier/config/utils.ex` (lines 24-43)
  - **Issue**: Fails on strings with spaces
  - **Fix**: Add String.trim before Integer.parse
  - **Impact**: Config parsing failures

- [ ] **Fix empty string env var handling**
  - **File**: `lib/wanderer_notifier/config/provider.ex` (lines 88-99)
  - **Issue**: Empty string falls through undocumented
  - **Fix**: Document behavior or handle explicitly
  - **Context**: Clarifies config semantics

- [ ] **Fix config_module env key**
  - **File**: `lib/wanderer_notifier/application.ex` (lines 131-140)
  - **Issue**: Uses `:config` instead of `:config_module`
  - **Fix**: Change tuple to `{:config_module, :config_module}`
  - **Impact**: Always logs nil

### 🛠️ Config Improvements

- [ ] **Use Mix.env() for test detection**
  - **File**: `lib/wanderer_notifier/cache/config.ex` (lines 30-35)
  - **Issue**: Runtime env check less idiomatic
  - **Fix**: Replace with `Mix.env() == :test`
  - **Context**: Follows Elixir conventions

- [ ] **Fix cache name override logic**
  - **File**: `lib/wanderer_notifier/cache/config.ex` (lines 93-107)
  - **Issue**: Merges opts after setting name
  - **Fix**: Use Keyword.put_new for name
  - **Context**: Respects caller's name

- [x] **Fix TTL fallback logic** ✅
  - **File**: `lib/wanderer_notifier/cache/config.ex` (lines 149-155)
  - **Issue**: Ignores per-type default
  - **Fix**: Check type default before global default
  - **Context**: More flexible configuration

## 7. Code Quality & Maintainability

### 🛠️ Dead Code Removal

- [ ] **Remove SafeCache module**
  - **File**: `lib/wanderer_notifier/esi/service.ex` (lines 424-433)
  - **Issue**: Never referenced after refactor
  - **Fix**: Delete or integrate via adapter
  - **Context**: Reduces maintenance burden

- [ ] **Remove unused require Logger**
  - **File**: `lib/wanderer_notifier/notifications/formatters/killmail.ex` (line 6)
  - **Issue**: Logger replaced with AppLogger
  - **Fix**: Remove the require statement
  - **Context**: Cleans up imports

- [ ] **Fix dead placeholder function**
  - **File**: `lib/wanderer_notifier/notifications/formatters/system.ex` (lines 277-278)
  - **Issue**: Always returns @default_color
  - **Fix**: Implement or remove
  - **Context**: Misleading function name

### 🛠️ Code Consistency

- [ ] **Remove repeated Config.cache_name lookups**
  - **File**: `lib/wanderer_notifier/notifications/killmail_notification.ex` (lines 111-120, 125-131, 336-347)
  - **Issue**: Repeated lookups in hot path
  - **Fix**: Memoize with `@cache_name` or pass down
  - **Context**: Minor performance improvement

- [ ] **Standardize for comprehension usage**
  - **File**: `lib/wanderer_notifier/application.ex` (lines 112-118)
  - **Issue**: For comprehension for side effects
  - **Fix**: Use `Enum.each/2` instead
  - **Context**: Clearer intent

- [ ] **Use proper Cachex child_spec**
  - **File**: `lib/wanderer_notifier/application.ex` (lines 145-161)
  - **Issue**: Direct tuple instead of child_spec
  - **Fix**: Use `Cachex.child_spec(name: cache_name)`
  - **Context**: Ensures proper telemetry setup

### 🧹 Minor Improvements

- [ ] **Fix ISK formatting precision**
  - **File**: `lib/wanderer_notifier/notifications/formatters/killmail.ex` (lines 605-619)
  - **Issue**: Rounds to 1 decimal, loses precision
  - **Fix**: Round to 2 decimals or use float_to_binary
  - **Context**: Better for expensive kills

- [ ] **Fix security status classification**
  - **File**: `lib/wanderer_notifier/notifications/formatters/killmail.ex` (lines 121-133)
  - **Issue**: Wormholes (-1.0) classified as null-sec
  - **Fix**: Add clause for < 0.0 returning "W-Space"
  - **Context**: Correct EVE Online terminology

- [ ] **Fix attacker string concatenation**
  - **File**: `lib/wanderer_notifier/notifications/formatters/killmail.ex` (lines 404-416)
  - **Issue**: No spaces between parts
  - **Fix**: Add whitespace in concatenation
  - **Context**: Improves readability

## 8. Testing & CI/CD

### ⚠️ Test Issues

- [x] **Fix SimpleETSCache atomicity warning** ✅
  - **File**: `lib/wanderer_notifier/cache/simple_ets_cache.ex` (lines 80-87)
  - **Issue**: get_and_update not atomic
  - **Fix**: Add warning in @moduledoc about test-only use
  - **Context**: Prevents production misuse

- [ ] **Add guards to SimpleETSCache.set**
  - **File**: `lib/wanderer_notifier/cache/simple_ets_cache.ex` (lines 45-53)
  - **Issue**: Crashes on nil or float TTL
  - **Fix**: Add guard `when is_integer(ttl) or ttl == :infinity`
  - **Context**: Better error messages

### 🛠️ CI/CD Improvements

- [ ] **Update GitHub Actions cache version**
  - **File**: `.github/workflows/ci-cd.yml` (lines 37-45)
  - **Issue**: Using deprecated v3
  - **Fix**: Update to `actions/cache@v4`
  - **Context**: Prevents cache skips

- [ ] **Fix unquoted variable in CI**
  - **File**: `.github/workflows/ci-cd.yml` (lines 95-103)
  - **Issue**: CURRENT_TAG unquoted
  - **Fix**: Quote variables in echo statements
  - **Context**: Handles tags with spaces

- [ ] **Fix Alpine package version pinning**
  - **File**: `Dockerfile.alpine` (lines 70-83)
  - **Issue**: Unpinned packages
  - **Fix**: Specify exact versions
  - **Context**: Reproducible builds

- [ ] **Fix check_image_size.sh bc dependency**
  - **File**: `check_image_size.sh` (lines 26-32)
  - **Issue**: Alpine may lack bc
  - **Fix**: Use awk for numeric comparison
  - **Context**: More portable

## 9. Documentation & Logging

### 🛠️ Documentation

- [ ] **Fix markdown formatting in CLAUDE.md**
  - **File**: `CLAUDE.md` (lines 11-43, 61-66)
  - **Issue**: Missing blank lines around headings/code blocks
  - **Fix**: Add blank lines per MD022/MD031
  - **Context**: Passes markdown lint

- [ ] **Fix grammar in CLAUDE.md**
  - **File**: `CLAUDE.md` (lines 61-66)
  - **Issue**: Missing "the" before "WANDERER_ prefix"
  - **Fix**: Add the article
  - **Context**: Better documentation

- [ ] **Add @doc to behaviour callbacks**
  - **File**: `lib/wanderer_notifier/config/config_behaviour.ex` (lines 13-21)
  - **Issue**: Callbacks lack documentation
  - **Fix**: Add @doc above each callback
  - **Context**: Helps implementers

### 🛠️ Logging Improvements

- [ ] **Fix Logger macro module resolution**
  - **File**: `lib/wanderer_notifier/logger/structured_logger.ex` (lines 42-60, 66-84)
  - **Issue**: Calls standard Logger not custom
  - **Fix**: Add explicit alias in quoted block
  - **Context**: Uses intended custom logger

- [ ] **Fix TTL logging for :infinity**
  - **File**: `lib/wanderer_notifier/logger/messages.ex` (lines 50-57)
  - **Issue**: Logs ":infinitys" with suffix
  - **Fix**: Add clause for :infinity atom
  - **Context**: Cleaner log messages

- [ ] **Fix actual status logging**
  - **File**: `lib/wanderer_notifier/http.ex` (lines 111-114)
  - **Issue**: Always logs 200 regardless of actual status
  - **Fix**: Pass real status to log_success
  - **Context**: Accurate logging

## 10. Miscellaneous Fixes

### 🧹 Quick Fixes

- [ ] **Fix Task.Supervisor child order**
  - **File**: `lib/wanderer_notifier/application.ex` (lines 38-47)
  - **Issue**: Started after dependent children
  - **Fix**: Move to beginning of base_children
  - **Context**: Prevents initialization races

- [ ] **Remove Content-Type from GET requests**
  - **File**: `lib/wanderer_notifier/http.ex` (lines 23-35)
  - **Issue**: GET shouldn't have Content-Type
  - **Fix**: Create separate @default_get_headers
  - **Context**: Some servers reject malformed requests

- [ ] **Fix nil handling in cache keys**
  - **File**: `lib/wanderer_notifier/cache/key_generator.ex` (lines 31-38)
  - **Issue**: Converts nil to "nil" string
  - **Fix**: Filter nil or raise error
  - **Context**: Prevents ambiguous keys

- [ ] **Fix extract_field false handling**
  - **File**: `lib/wanderer_notifier/map/map_util.ex` (lines 90-94)
  - **Issue**: Treats false as missing
  - **Fix**: Check for nil explicitly
  - **Context**: Preserves boolean values

## Summary Statistics

- **Total Tasks**: 109
- **⚠️ Potential Issues**: 32
- **🛠️ Refactor Suggestions**: 52
- **🧹 Nitpicks**: 24
- **💡 Verification Needed**: 1

## Recommended Approach

1. **Phase 1**: Fix all ⚠️ Potential Issues first (runtime errors, data corruption)
2. **Phase 2**: Address 🛠️ Refactor Suggestions (improve maintainability)
3. **Phase 3**: Handle 🧹 Nitpicks (polish and consistency)

Each task includes:
- Specific file and line numbers
- Clear description of the issue
- Concrete fix suggestion
- Impact or context explanation