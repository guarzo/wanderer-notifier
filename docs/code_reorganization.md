# Code Reorganization

This document outlines the reorganization of several core modules to improve the project structure and maintainability.

## Reorganized Modules

| Original Location                           | New Location                                     | Purpose                    |
| ------------------------------------------- | ------------------------------------------------ | -------------------------- |
| `lib/wanderer_notifier/config.ex`           | `lib/wanderer_notifier/config/config.ex`         | Application configuration  |
| `lib/wanderer_notifier/debug.ex`            | `lib/wanderer_notifier/utilities/debug.ex`       | Development utilities      |
| `lib/wanderer_notifier/logger_behaviour.ex` | `lib/wanderer_notifier/core/logger_behaviour.ex` | Logger behavior definition |
| `lib/wanderer_notifier/logger.ex`           | `lib/wanderer_notifier/core/logger.ex`           | Enhanced logging utility   |
| `lib/wanderer_notifier/repo.ex`             | `lib/wanderer_notifier/data/repo.ex`             | Ecto repository            |
| `lib/wanderer_notifier/repository.ex`       | `lib/wanderer_notifier/data/repository.ex`       | Data access layer          |
| `lib/wanderer_notifier/domain.ex`           | `lib/wanderer_notifier/resources/domain.ex`      | Ash framework domain       |

## Backward Compatibility

To maintain backward compatibility, the original module names have been preserved as aliases that delegate to the new implementations. This allows existing code to continue functioning while encouraging migration to the new module paths.

For example:

```elixir
defmodule WandererNotifier.Config do
  @moduledoc """
  Alias module for WandererNotifier.Config.Config.

  This module exists for backward compatibility and delegates to the new location.
  Consider updating references to use WandererNotifier.Config.Config directly.
  """

  defdelegate map_url, to: WandererNotifier.Config.Config
  defdelegate map_token, to: WandererNotifier.Config.Config
  # ...other delegations
end
```

## Benefits of Reorganization

1. **Improved Code Organization**: Modules are now grouped by functionality rather than kept in the root directory
2. **Better Discoverability**: Related modules are now located in the same directory
3. **Reduced Namespace Clutter**: The root namespace is less cluttered
4. **Consistent Structure**: The project now follows a more consistent structure throughout

## Migration Plan

1. **Phase 1 (Completed)**: Move the modules to their new locations
2. **Phase 2 (Completed)**: Create alias modules for backward compatibility
3. **Phase 3 (Completed)**: Update references in the codebase to use the new module paths
4. **Phase 4 (Completed)**: Remove the alias modules since all references have been updated

## Module Details

### Config Module

The `Config` module has been moved to `Config.Config` to align with the existing pattern of other configuration modules in the `config/` directory.

### Logger Module

The `Logger` and `LoggerBehaviour` modules have been moved to the `core/` directory since logging is a core functionality that spans the entire application.

### Repository and Repo Modules

The data-related modules have been consolidated in the `data/` directory to better organize database access.

### Debug Module

Development utilities have been moved to a dedicated `utilities/` directory to separate them from core application code.

### Domain Module

The Ash domain module has been moved to the `resources/` directory to be closer to the resources it defines.
