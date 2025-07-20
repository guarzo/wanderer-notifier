# ADR-004: Configuration Management Approach

## Status

Accepted

## Context

The original configuration system had several pain points:
- Configuration scattered across multiple modules
- Mix of compile-time and runtime configuration without clear patterns
- Complex configuration validation spread throughout the codebase
- Difficult to understand what configuration was available
- Feature flags implemented inconsistently
- Environment variable handling was verbose and repetitive

The system used:
- Manual `Application.get_env/3` calls throughout the codebase
- No centralized validation
- Inconsistent default value handling
- Complex feature flag logic scattered across modules

## Decision

We implemented a macro-based configuration system with centralized management:

1. **Macro-Based Configuration** (`WandererNotifier.Shared.Config`)
   - `defconfig` macro for defining configuration options
   - Automatic getter function generation
   - Built-in validation and type checking
   - Centralized default value management

2. **Centralized Configuration Module**
   - All configuration options defined in one place
   - Clear documentation of each option
   - Standardized environment variable naming
   - Automatic validation on application startup

3. **Feature Flag System**
   - Consistent `_ENABLED` suffix for feature flags
   - Boolean configuration with sensible defaults
   - Easy to add new feature flags

4. **Validation Framework**
   - Automatic validation of all configuration at startup
   - Clear error messages for invalid configuration
   - Type checking and format validation
   - Required vs optional configuration handling

5. **Environment Variable Standards**
   - Removed redundant `WANDERER_` prefix for simplicity
   - Consistent naming conventions
   - Clear mapping between config keys and env vars

## Consequences

### Positive
- **Single Source of Truth**: All configuration in one module
- **Automatic Validation**: Configuration errors caught at startup
- **Better Developer Experience**: Clear, documented configuration options
- **Easier Testing**: Configuration can be easily mocked
- **Reduced Boilerplate**: Macros generate repetitive code
- **Consistent Patterns**: All configuration follows same patterns

### Negative
- **Macro Complexity**: Understanding macros requires Elixir knowledge
- **Compile-time Dependencies**: Configuration changes require recompilation
- **Learning Curve**: New approach requires team education

### Neutral
- **Migration Effort**: All configuration calls needed updating
- **New Conventions**: Team needs to learn new configuration patterns

## Implementation Details

### Configuration Definition
```elixir
defmodule WandererNotifier.Shared.Config do
  use WandererNotifier.Shared.Config.Macros

  # Basic configuration with validation
  defconfig :discord_bot_token, :string,
    env: "DISCORD_BOT_TOKEN",
    required: true,
    validator: &validate_discord_token/1

  # Configuration with default value
  defconfig :websocket_url, :string,
    env: "WEBSOCKET_URL", 
    default: "ws://host.docker.internal:4004"

  # Feature flag
  defconfig :notifications_enabled, :boolean,
    env: "NOTIFICATIONS_ENABLED",
    default: true
end
```

### Usage Throughout Codebase
```elixir
# Before (verbose, scattered)
bot_token = Application.get_env(:wanderer_notifier, :discord_bot_token)
if is_nil(bot_token), do: raise "Discord bot token required"

# After (clean, validated)
bot_token = Config.discord_bot_token()
# Already validated at startup, guaranteed to exist
```

### Validation Framework
```elixir
# Automatic validation with clear error messages
defp validate_discord_token(token) when is_binary(token) do
  if String.starts_with?(token, ["Bot ", "Bearer "]) do
    {:ok, token}
  else
    {:error, "Discord token must start with 'Bot ' or 'Bearer '"}
  end
end
```

### Feature Flag Pattern
```elixir
# Consistent feature flag naming and usage
if Config.notifications_enabled?() do
  send_notification(message)
end
```

## Migration Notes

### Before (Manual Configuration)
```elixir
# Scattered throughout codebase
case Application.get_env(:wanderer_notifier, :discord_bot_token) do
  nil -> {:error, "Discord bot token required"}
  token -> validate_and_use_token(token)
end
```

### After (Macro-Generated Configuration)
```elixir
# Centralized with automatic validation
token = Config.discord_bot_token()  # Already validated
use_token(token)
```

### Configuration File Structure
```elixir
# config/config.exs - Compile-time defaults
config :wanderer_notifier,
  default_timeout: 30_000

# config/runtime.exs - Runtime environment loading  
import WandererNotifier.Shared.Config
load_runtime_config()
```

## Benefits Realized

1. **Startup Validation**: All configuration errors caught before application starts
2. **Clear Documentation**: Configuration options are self-documenting
3. **Type Safety**: Configuration values are validated for correct types
4. **Easier Debugging**: Configuration problems are immediately obvious
5. **Reduced Errors**: No more runtime configuration surprises

## Alternatives Considered

1. **Manual Configuration**: Rejected due to boilerplate and error-proneness
2. **External Configuration Library**: Rejected to reduce dependencies
3. **GenServer-based Configuration**: Rejected as overkill for static configuration
4. **YAML/JSON Configuration**: Rejected due to Elixir ecosystem preferences

## Trade-offs

### Macro vs Manual
- **Pros**: Less boilerplate, automatic validation, consistent patterns
- **Cons**: More complex to understand, compile-time dependencies

### Centralized vs Distributed
- **Pros**: Single source of truth, easier to audit, better validation
- **Cons**: Large single file, potential merge conflicts

## Future Considerations

- Consider configuration schema documentation generation
- Evaluate configuration hot-reloading for development
- Monitor configuration module size and consider splitting if needed

## References

- Elixir configuration best practices
- Application configuration patterns in OTP
- Sprint 2 configuration refactoring goals