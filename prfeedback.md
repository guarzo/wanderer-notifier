# PR Feedback Review

This document contains code review feedback items that need to be addressed in the Wanderer Notifier codebase.

## High Priority Issues

### 1. Inefficient Cache Lookups with Nil System IDs

**File:** `lib/wanderer_notifier/notifications/formatters/killmail.ex:85-90`

**Issue:** The code calls the cache lookup function even when `system_id` is nil, which is inefficient.

**Context:** In the `extract_kill_context/1` function, the system name resolution chain always calls `WandererNotifier.Killmail.Cache.get_system_name(system_id)` as a fallback, even when `system_id` is nil. This results in unnecessary cache operations.

**Fix:** Modify the code to only call `WandererNotifier.Killmail.Cache.get_system_name(system_id)` if `system_id` is not nil, skipping the cache lookup when `system_id` is missing.

---

**File:** `lib/wanderer_notifier/killmail/killmail.ex:178-182`

**Issue:** Similar issue in the killmail struct creation - cache lookup called even when `system_id` is nil.

**Context:** In the `new/3` function that creates killmail structs from ZKB and ESI data, the system name resolution always falls back to the cache lookup regardless of whether `system_id` exists.

**Fix:** First check if `system_id` is not nil before calling the cache function; if `system_id` is nil, directly assign "Unknown" as the system_name fallback.

### 2. Invalid Test Data Generation

**File:** `test/wanderer_notifier/killmail/json_encoder_property_test.exs:309-317`

**Issue:** The `killmail_time` is generated using `string(:alphanumeric)`, which can produce invalid timestamps.

**Context:** Property-based tests are generating random alphanumeric strings for timestamp fields, which don't represent realistic killmail data and may cause encoding/decoding issues.

**Fix:** Replace this with a generator that produces ISO-8601 formatted datetime strings to ensure the test data is realistic and can better validate the encoder and decoder handling of actual timestamp formats.

### 3. Cache TTL Handling Issues

**File:** `lib/wanderer_notifier/map/clients/base_map_client.ex:75-82`

**Issue:** The fallback clause in the TTL conversion returns 0, causing immediate cache expiry.

**Context:** In the `set/4` function's TTL conversion logic, invalid TTL values default to 0 milliseconds, which causes cached data to expire immediately rather than handling the error appropriately.

**Fix:** Change the fallback to return `:error` instead of 0, and update the `set/4` function call to check for `:error` and skip the cache write when TTL is invalid.

### 4. Fragile Endpoint Detection

**File:** `lib/wanderer_notifier/map/clients/base_map_client.ex:295-301`

**Issue:** The function `add_query_params/1` uses a hard-coded substring check on `endpoint()` to decide if a slug query parameter is needed.

**Context:** The current implementation checks if the endpoint URL contains "user-characters" to determine if it needs to add a slug query parameter. This string-based approach is brittle and doesn't follow the behavior-based design pattern used elsewhere in the codebase.

**Fix:** Refactor by defining a `@callback requires_slug?()` that returns a boolean, defaulting to false in the base client macro, and override it to true in clients like CharactersClient that need the slug. Then update `add_query_params/1` to call `requires_slug?()` instead of checking the endpoint string.

## Code Quality Issues

### 5. Dead Code Removal

**File:** `lib/wanderer_notifier/killmail/cache.ex:14-23`

**Issue:** Remove the unused process-dictionary cache.

**Context:** The `@system_names_cache_key` is still declared and written to, but no read path exists after the latest refactor. This creates dead code that adds mental overhead.

**Fix:** Remove the unused process dictionary cache code:
```elixir
-# System name cache - process dictionary for performance
-@system_names_cache_key :system_names_cache
...
- # Initialize the system names cache in the process dictionary
- Process.put(@system_names_cache_key, %{})
```

### 6. Configuration Consistency

**File:** `lib/wanderer_notifier/killmail/cache.ex:166-170`

**Issue:** Use the existing `CacheConfig.cache_name/0` helper.

**Context:** Hard-coding the cache name here re-introduces configuration divergence that was previously addressed. The codebase has a centralized cache configuration helper that should be used consistently.

**Fix:** Replace hard-coded cache name with the shared helper:
```elixir
- cache_name = Application.get_env(:wanderer_notifier, :cache_name, :wanderer_cache)
+ cache_name = CacheConfig.cache_name()
```

### 7. Hard-coded TTL Values

**File:** `lib/wanderer_notifier/killmail/cache.ex:180-181`

**Issue:** Hard-coded 24h TTL should be configuration-driven.

**Context:** The `:timer.hours(24)` literal prevents operators from tuning cache TTL without code changes. The codebase follows a pattern of making cache TTLs configurable.

**Fix:** Fetch the value through configuration:
```elixir
- ttl_ms = :timer.hours(24)
+ ttl_ms = WandererNotifier.Cache.Config.ttl_for(:system_name) |> :timer.seconds()
```

### 8. Port Validation Issues

**File:** `lib/wanderer_notifier/config/utils.ex:68-75`

**Issue:** Trailing characters in port strings still slip through.

**Context:** The port validation logic accepts values like "8080abc" without warning, which could lead to silent misconfiguration in production environments.

**Fix:** Only accept clean integer conversions:
```elixir
- {int_port, _} ->
-   validate_port_range(int_port)
+ {int_port, ""} ->
+   validate_port_range(int_port)
+ {_int_port, _rest} ->
+   Logger.warning("Port string '#{port}' contains non-numeric trailing characters – using default #{@default_port}.")
+   @default_port
```

### 9. Cache Adapter Success Handling

**File:** `lib/wanderer_notifier/map/clients/base_map_client.ex:83-89`

**Issue:** Broaden success clause for `Cache.Adapter.set/4`.

**Context:** The adapter may legitimately return `:ok` or other `{:ok, value}` shapes. Currently, anything other than `{:ok, _}` is logged as a cache error even when the write succeeded.

**Fix:** Handle both success patterns:
```elixir
case WandererNotifier.Cache.Adapter.set(cache_name, cache_key, data, ttl_ms) do
  {:ok, _} ->
    {:ok, data}
+ :ok ->
+   {:ok, data}
```

### 10. Exception Handling Scope

**File:** `lib/wanderer_notifier/map/clients/characters_client.ex:61-71`

**Issue:** Broad rescue still swallows all exceptions.

**Context:** Catching every exception masks bugs unrelated to struct construction (e.g., nil derefs). The rescue should be specific to the expected error type from `MapCharacter.new/1`.

**Fix:** Rescue only `ArgumentError`:
```elixir
- try do
-   MapCharacter.new(character)
- rescue
-   e ->
+ try do
+   MapCharacter.new(character)
+ rescue
+   e in ArgumentError ->
```

### 11. Error Pattern Matching

**File:** `lib/wanderer_notifier/notifiers/discord/notifier.ex:424-428`

**Issue:** Pattern-match does not align with `ESIService.get_system/2` error tuples.

**Context:** `ESIService.get_system/2` returns `{:error, {:system_not_found, system_id}}`, not `{:error, :not_found}`. The current match will fall through to the catch-all clause, returning nil instead of the intended "Unknown-#{system_id}" sentinel.

**Fix:** Correct the error pattern matching:
```elixir
case ESIService.get_system(system_id, []) do
  {:ok, system_info} ->
    Map.get(system_info, "name")
- {:error, :not_found} -> "Unknown-#{system_id}"
+ {:error, {:system_not_found, ^system_id}} ->
+   "Unknown-#{system_id}"
+ {:error, {:http_error, _}} ->
+   "Unknown-#{system_id}"
```

### 12. Function Naming Clarity

**File:** `lib/wanderer_notifier/killmail/cache.ex:88-96, 140-146`

**Issue:** Two `get_cached_kill_ids` variants cause naming friction.

**Context:** Having both `get_cached_kill_ids/0` (tuple return) and `get_cached_kill_ids/1` (list return) forces the reader to track arity-specific semantics, making the API confusing.

**Fix:** Rename one helper (e.g., `fetch_cached_kill_ids/1`) or keep return shapes consistent (either always tuple or always raw list) to improve readability and lower the risk of accidental misuse.

## Additional Items

### 13. Consistency Issue

**File:** `lib/wanderer_notifier/killmail/killmail.ex:206-210`

**Issue:** Same nil-guard issue as above – apply the same fix in `from_map/1` for consistency.

**Context:** This appears to be the same system_id nil-checking issue that needs to be addressed in the `from_map/1` function to maintain consistency with the fixes applied elsewhere.