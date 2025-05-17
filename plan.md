# Wanderer Notifier Refactoring Plan

## 1. Directory Restructuring

Reorganize the codebase into clear domain contexts:

✅ Created base directory structure

```
lib/wanderer_notifier/
├── application.ex
├── api/                  # HTTP interface
│   ├── pipeline.ex
│   └── controllers/
│       ├── killmail_controller.ex
│       ├── map_controller.ex
│       └── license_controller.ex
├── cache/                # Cache contracts & implementations
│   ├── behaviour.ex
│   ├── cachex.ex
│   ├── key.ex            ✅ DONE: Unified cache key generation
├── clients/              # External API clients
│   ├── http/
│   │   ├── behaviour.ex
│   │   └── httpoison.ex
│   └── esi/
│       ├── client.ex
│       └── zkill_client.ex
├── config/               # Runtime configs per context
│   ├── http.ex           ✅ DONE: Created HTTP config
│   ├── websocket.ex      ✅ DONE: Created WebSocket config
│   ├── notification.ex   ✅ DONE: Created Notification config
│   ├── license.ex        ✅ DONE: Created License config
│   └── utils.ex          ✅ DONE: Created Utils config helpers
├── common/               # Shared helpers & types
│   ├── tracking_utils.ex
│   └── error_helpers.ex  ✅ DONE: Created error logging helpers
├── killmail/             # Killmail business logic
│   ├── pipeline.ex
│   ├── processor.ex
│   └── schema.ex
├── mapping/              # Map-related logic
│   ├── template_repo.ex
│   ├── api_client.ex
│   └── transformations.ex
├── license/              # License business logic
│   ├── license.ex
│   └── mapping.ex
├── notifications/        # Notification services
│   ├── notifier.ex
│   └── formatters/
│       ├── character.ex
│       └── system.ex
├── scheduling/           # Background jobs
│   ├── scheduler.ex
│   └── jobs/
│       ├── killmail_fetch.ex
│       └── mapping_refresh.ex
└── logger/               # Logging infrastructure
    ├── logger.ex
    └── backend.ex
```

### Benefits

- **One-thing-per-directory**: Clear location for domain-specific code
- **Domain isolation**: Proper boundaries between contexts
- **Faster recompilation**: Changes only affect relevant modules
- **Clear dependency flow**: Prevents circular dependencies

## 2. Config Module Refactoring

✅ Split the monolithic Config module into focused modules by concern:

### 2.1. Identify Concern Boundaries

| Concern       | Example functions                                       | Status  |
| ------------- | ------------------------------------------------------- | ------- |
| HTTP          | http_host/0, http_port/0, http_scheme/0                 | ✅ DONE |
| WebSocket     | ws_endpoint/0, ws_timeout/0                             | ✅ DONE |
| Notifications | discord_token/0, notification_ttl/0                     | ✅ DONE |
| License       | license_key/0, license_ttl/0                            | ✅ DONE |
| ESI           | esi_base_url/0, esi_token/0                             | ✅ DONE |
| Generic Utils | parse_int/1, nil_or_empty?/1, parse_list/1, fetch_env/1 | ✅ DONE |

### 2.2. Create Modules Per Concern

✅ Created config modules:

```
lib/wanderer_notifier/config/
├── http.ex          ✅ DONE
├── websocket.ex     ✅ DONE
├── notification.ex  ✅ DONE
├── esi.ex           ✅ DONE
├── license.ex       ✅ DONE
└── utils.ex         ✅ DONE
```

## 3. Specific Code Improvements

### 3.1. Unify Cache-Key Generation ✅ DONE

**Problem**: Multiple duplicate functions for cache keys.

**Solution**: Created a centralized key builder in `lib/wanderer_notifier/cache/key.ex` with the following interface:

```elixir
# Create a cache key object
key_obj = WandererNotifier.Cache.Key.new(:killmail, killmail_id)

# Convert to string
key_str = WandererNotifier.Cache.Key.to_string(key_obj)
# "wn:killmail:12345"

# Or do it all in one step
key_str = WandererNotifier.Cache.Key.for(:killmail, killmail_id)
# "wn:killmail:12345"
```

### 3.2. Extract Shared Error-Logging Patterns ✅ DONE

**Problem**: Duplicate error handling code across modules.

**Solution**: Created error handling macros in `lib/wanderer_notifier/common/error_helpers.ex` with the following interfaces:

```elixir
# Basic API error handling
with_api_log "fetch_user" do
  api_client.get_user(user_id)
end

# Custom error handling
with_custom_error_handler "process_data", fn e -> {:error, e.message} end do
  process_data(data)
end

# Function-based approach
safe_call(fn -> some_function_that_might_fail() end, "operation_name")
```

## 4. Bug Fixes and Optimizations

1. **Fix in web_controller.ex (lines 133-140)**: Eliminate redundant `Config.features()` calls ✅ DONE

   ```elixir
   features_list = Config.features()
   features_map = Enum.into(features_list, %{})
   enabled = Map.get(features_map, "feature_name", false)
   ```

2. **Fix in application.ex (lines 78-100)**: Replace `Enum.map` with `Enum.each` in `log_environment_variables` ✅ DONE

3. **Fix in runtime.exs (lines 111-112, 119-120, 127-128)**: Replace incorrect `System.get_env/2` usage: ✅ DONE

   ```elixir
   # Replace this:
   System.get_env("VAR", "default")
   # With this:
   System.get_env("VAR") || "default"
   ```

4. **Fix in application.ex (lines 146-168)**: Add production environment guard to `reload/1`: ✅ DONE

   ```elixir
   def reload(mods) when get_env() != :prod do
     # existing implementation
   end

   def reload(_modules) do
     AppLogger.config_error("Module reloading is disabled in production")
     {:error, :disabled_in_production}
   end
   ```

5. **Fix in config.exs (lines 6-10)**: Consolidate duplicate scheduler flags ✅ DONE

   - Scheduler flags were already consolidated in a proper map structure

6. **Fix in config.exs (lines 104-110)**: Remove references to deleted ESI.Service module ✅ DONE

   - ESI.Service reference was already removed from the configuration

7. **Fix in notification_controller.ex (lines 14-17)**: Distinguish not-found from internal failures ✅ DONE

   - Added specific error cases with appropriate HTTP status codes

8. **Fix in notification_controller.ex (lines 55-59)**: Improve error logging ✅ DONE

   - Added additional logging for missing configuration

9. **Fix in notification_controller.ex (lines 43-46)**: Guard against nil from Config.features/0: ✅ DONE

   ```elixir
   # Get features with a nil guard
   features = Config.features() || []
   features_map = Enum.into(features, %{})
   ```

## 5. Migration Steps

1. Create new folders under `lib/wanderer_notifier/` per the directory structure
2. Move files to their new homes, updating module namespaces
3. Update aliases/imports in moved files to reflect new structure
4. Update `mix.exs` and test structure to mirror lib/
5. Run `mix compile` and fix any missing references
6. Update tests to point to new module names
7. Delete empty old directories once all tests pass

## 6. Documentation

Create a high-level architectural README documenting:

- Data flows (e.g., killmail flows from ZKill → Killmail.Processor → cache → API)
- Scheduler trigger mechanisms
- Configuration source locations (compile vs runtime)

## Progress Summary

### Completed Tasks

1. **Directory Structure**:

   - Created base directory structure according to the plan
   - Established foundation for domain-driven organization

2. **Config Module Refactoring**:

   - Implemented all 6 of the planned config modules (http, websocket, notification, license, esi, utils)
   - Extracted specific concerns into their own modules
   - Improved code organization and structure

3. **Specific Code Improvements**:

   - Created the Cache.Key module for unified cache key generation
   - Implemented ErrorHelpers module with common error handling patterns

4. **Bug Fixes**:

   - Fixed application.ex to use Enum.each in log_environment_variables
   - Added production environment guard to reload/1 function
   - Fixed System.get_env/2 usage in runtime.exs
   - Fixed redundant Config.features() calls in web_controller.ex
   - Verified scheduler flags structure in config.exs (already consolidated)
   - Verified ESI.Service references in config.exs (already removed)
   - Improved error handling in notification_controller.ex
   - Added guard against nil from Config.features/0

5. **Migration and Testing**:

   - Updated imports/aliases in files that reference the old Config module
   - Updated references to old config functions with the new namespaced ones
   - Fixed compilation errors and many warnings
   - Implemented missing functions in Factory and Dispatcher modules
   - Created needed formatters for notifications

6. **Documentation**:
   - Created comprehensive ARCHITECTURE.md detailing system components, data flows, scheduler mechanisms, and configuration sources

### Pending Tasks

1. **Address Remaining Format Warnings** (Optional):

   - There are some remaining warnings about mismatched formatter methods, but these don't prevent the code from compiling
   - If needed, add the missing formatter methods or update the call sites to use the proper method names

2. **Testing**:

   - Run integration tests to validate all changes
   - Ensure the application starts correctly in all environments

3. **Final Cleanup**:
   - Delete empty old directories if any remain
