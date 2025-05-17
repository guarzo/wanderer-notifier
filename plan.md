# Wanderer Notifier Refactoring Plan

## 1. Directory Restructuring

Reorganize the codebase into clear domain contexts:

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
│   └── cachex.ex
├── clients/              # External API clients
│   ├── http/
│   │   ├── behaviour.ex
│   │   └── httpoison.ex
│   └── esi/
│       ├── client.ex
│       └── zkill_client.ex
├── config/               # Runtime configs per context
│   ├── http.ex
│   ├── websocket.ex
│   ├── notification.ex
│   └── utils.ex
├── common/               # Shared helpers & types
│   ├── tracking_utils.ex
│   └── error_helpers.ex
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

Split the monolithic Config module into focused modules by concern:

### 2.1. Identify Concern Boundaries

| Concern       | Example functions                                       |
| ------------- | ------------------------------------------------------- |
| HTTP          | http_host/0, http_port/0, http_scheme/0                 |
| WebSocket     | ws_endpoint/0, ws_timeout/0                             |
| Notifications | discord_token/0, notification_ttl/0                     |
| License       | license_key/0, license_ttl/0                            |
| ESI           | esi_base_url/0, esi_token/0                             |
| Generic Utils | parse_int/1, nil_or_empty?/1, parse_list/1, fetch_env/1 |

### 2.2. Create Modules Per Concern

```
lib/wanderer_notifier/config/
├── http.ex
├── websocket.ex
├── notification.ex
├── esi.ex
├── license.ex
└── utils.ex
```

## 3. Specific Code Improvements

### 3.1. Unify Cache-Key Generation

**Problem**: Multiple duplicate functions for cache keys.

**Solution**: Create a centralized key builder:

```elixir
defmodule WandererNotifier.Cache.Key do
  @moduledoc "Generic cache-key generator."

  @type t :: %__MODULE__{prefix: String.t(), entity: atom(), id: term()}
  defstruct [:prefix, :entity, :id]

  @spec new(atom(), term()) :: t()
  def new(entity, id) when is_atom(entity) do
    %__MODULE__{
      prefix: Application.get_env(:wanderer_notifier, :cache_prefix, "wn"),
      entity: entity,
      id: id
    }
  end

  @spec to_string(t()) :: String.t()
  def to_string(%__MODULE__{prefix: pre, entity: ent, id: id}) do
    "#{pre}:#{ent}:#{id}"
  end
end
```

**Usage**: `key = WandererNotifier.Cache.Key.new(:killmail, killmail_id) |> to_string()`

### 3.2. Extract Shared Error-Logging Patterns

**Problem**: Duplicate error handling code across modules.

**Solution**: Create a logging macro:

```elixir
defmodule WandererNotifier.Logging do
  @moduledoc "Macros for consistent API error handling."

  defmacro with_api_log(context, do: block) do
    quote do
      try do
        unquote(block)
      rescue
        e ->
          AppLogger.api_error(unquote(context), %{error: Exception.message(e)})
          {:error, :service_unavailable}
      end
    end
  end
end
```

## 4. Bug Fixes and Optimizations

1. **Fix in web_controller.ex (lines 133-140)**: Eliminate redundant `Config.features()` calls

   ```elixir
   features = Config.features()
   features_map = Enum.into(features, %{})
   enabled = Map.get(features_map, "feature_name", false)
   ```

2. **Fix in application.ex (lines 78-100)**: Replace `Enum.map` with `Enum.each` in `log_environment_variables`

3. **Fix in runtime.exs (lines 111-112, 119-120, 127-128)**: Replace incorrect `System.get_env/2` usage:

   ```elixir
   # Replace this:
   System.get_env("VAR", "default")
   # With this:
   System.get_env("VAR") || "default"
   ```

4. **Fix in application.ex (lines 146-168)**: Add production environment guard to `reload/1`:

   ```elixir
   def reload(mods) when get_env() != :prod do
     # existing implementation
   end
   ```

5. **Fix in config.exs (lines 6-10)**: Consolidate duplicate scheduler flags

6. **Fix in config.exs (lines 104-110)**: Remove references to deleted ESI.Service module

7. **Fix in notification_controller.ex (lines 14-17)**: Distinguish not-found from internal failures

8. **Fix in notification_controller.ex (lines 55-59)**: Improve error logging

9. **Fix in notification_controller.ex (lines 43-46)**: Guard against nil from Config.features/0:

   ```elixir
   features =
     Config.features()
     |> Kernel.||([])  # fall back to empty list

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

-- Other Stuff --

We want to segment the kill notifications based on characte