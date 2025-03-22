# Feature Flags

This document outlines the feature flag system used in the WandererNotifier application. Feature flags allow for selective enablement of functionality, making it easier to control application behavior without code changes.

## Overview

The WandererNotifier application uses a centralized feature flag system to control which features are active. This allows for:

1. Gradual rollout of new features
2. A/B testing of different functionality
3. Quick disabling of problematic features
4. Environment-specific feature activation
5. License-based feature access

## Core Feature Flag Module

Feature flags are managed through the `WandererNotifier.Core.Config.Features` module, which provides a consistent interface for checking feature status:

```elixir
defmodule WandererNotifier.Core.Config.Features do
  @moduledoc """
  Feature flag management for WandererNotifier.
  """

  # Feature flag structure
  @features %{
    notifications: %{
      enabled_var: "ENABLE_NOTIFICATIONS",
      channel_var: "DISCORD_CHANNEL_ID",
      default_enabled: true,
      description: "Master switch for all notifications"
    },
    kill_notifications: %{
      enabled_var: "ENABLE_KILL_NOTIFICATIONS",
      channel_var: "DISCORD_KILL_CHANNEL_ID",
      default_enabled: true,
      description: "Notifications for ship kills"
    },
    # ... other features
  }

  @doc """
  Checks if a feature is enabled.
  """
  def feature_enabled?(feature) when is_atom(feature) do
    case Map.get(@features, feature) do
      nil ->
        false
      feature_config ->
        env_var = feature_config.enabled_var
        default = feature_config.default_enabled
        parse_bool(System.get_env(env_var), default)
    end
  end

  # ... helper functions and shorthand access methods
end
```

## Shorthand Helper Functions

For commonly checked features, shorthand helper functions are provided:

```elixir
def notifications_enabled?(), do: feature_enabled?(:notifications)
def kill_notifications_enabled?(), do: feature_enabled?(:kill_notifications) && notifications_enabled?()
def system_notifications_enabled?(), do: feature_enabled?(:system_notifications) && notifications_enabled?()
def character_notifications_enabled?(), do: feature_enabled?(:character_notifications) && notifications_enabled?()
```

## Available Feature Flags

| Feature Flag              | Environment Variable             | Default | Description                                      |
| ------------------------- | -------------------------------- | ------- | ------------------------------------------------ |
| `notifications`           | `ENABLE_NOTIFICATIONS`           | `true`  | Master switch for all notifications              |
| `kill_notifications`      | `ENABLE_KILL_NOTIFICATIONS`      | `true`  | Kill notifications via WebSocket                 |
| `system_notifications`    | `ENABLE_SYSTEM_NOTIFICATIONS`    | `true`  | System tracking notifications                    |
| `character_notifications` | `ENABLE_CHARACTER_NOTIFICATIONS` | `true`  | Character tracking notifications                 |
| `charts`                  | `ENABLE_CHARTS`                  | `false` | Master switch for chart generation               |
| `map_charts`              | `ENABLE_MAP_CHARTS`              | `true`  | Map-based activity charts                        |
| `kill_charts`             | `ENABLE_KILL_CHARTS`             | `false` | Killmail charts and history                      |
| `node_chart_service`      | `ENABLE_NODE_CHART_SERVICE`      | `false` | Use Node.js chart service instead of QuickCharts |

- Note: Some chart types have been removed. The `map_charts` feature now only supports the activity_summary chart type.
  The activity_timeline and activity_distribution chart types are no longer available.

## Feature Dependencies

Some features depend on others. For example:

1. All notification types depend on the master `notifications` switch
2. Chart-specific features depend on the master `charts` switch
3. Some features have legacy environment variables that are checked for backward compatibility

These dependencies are handled in the helper functions:

```elixir
def charts_enabled?() do
  feature_enabled?(:charts)
end

def map_charts_enabled?() do
  feature_enabled?(:map_charts)
end

def kill_charts_enabled?() do
  feature_enabled?(:kill_charts) || killmail_persistence_enabled?()  # Legacy support
end
```

## Using Feature Flags in Code

Feature flags are used throughout the code to conditionally enable functionality:

```elixir
def process_kill(killmail) do
  if Features.kill_notifications_enabled?() do
    # Process the kill and send notification
    do_process_kill(killmail)
  else
    Logger.debug("Kill notifications disabled, skipping processing")
    {:ok, :skipped}
  end
end
```

## Feature-Specific Configuration

Each feature can have its own related configuration, particularly for notification channels:

```elixir
def discord_channel_id_for(feature) do
  case Map.get(@features, feature) do
    nil ->
      System.get_env("DISCORD_CHANNEL_ID")
    feature_config ->
      channel_var = feature_config.channel_var
      fallback = System.get_env("DISCORD_CHANNEL_ID")
      System.get_env(channel_var, fallback)
  end
end
```

This allows different notification types to be sent to different channels while maintaining a fallback to the main channel.

## License-Based Feature Flags

Some features may be restricted based on license level. These are checked through a combination of feature flags and license verification:

```elixir
def can_use_extended_tracking?() do
  feature_enabled?(:extended_tracking) && LicenseManager.has_feature?(:extended_tracking)
end
```

## Environment-Specific Configuration

Feature flags can be set differently per environment through environment variables. Common patterns include:

- Development environment: All features enabled for testing
- Production environment: Stable features enabled, experimental features disabled
- Staging environment: New features enabled for testing before production rollout

## Command-Line Feature Override

For testing purposes, features can be temporarily enabled through command-line arguments when starting the application:

```bash
ENABLE_NODE_CHART_SERVICE=true iex -S mix
```

## Best Practices

1. **Layer Feature Checks**: Place feature checks at the appropriate level of abstraction
2. **Default to Disabled**: New experimental features should default to disabled
3. **Document Dependencies**: Clearly document feature dependencies
4. **Graceful Degradation**: When features are disabled, provide fallbacks where appropriate
5. **Log Status**: Log feature flag status on application startup
6. **Clean Up Legacy Flags**: Remove feature flags for fully adopted features

## Monitoring Feature Usage

The application logs feature flag status on startup:

```
[info] WandererNotifier starting with features:
[info]   ✓ notifications
[info]   ✓ kill_notifications
[info]   ✓ system_notifications
[info]   ✓ character_notifications
[info]   ✗ charts
[info]   ✗ map_charts
```

This provides visibility into which features are active in each deployment.
