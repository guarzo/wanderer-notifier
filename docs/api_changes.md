# API Changes Documentation

## Migration from Proxy Modules to Direct Module References

This document outlines the API changes made during the refactoring to eliminate proxy modules and use direct module references in the codebase.

### Notifier Behaviour

**Previous Usage:**

```elixir
@behaviour WandererNotifier.NotifierBehaviour

@impl WandererNotifier.NotifierBehaviour
def send_message(message) do
  # Implementation
end
```

**Current Usage:**

```elixir
@behaviour WandererNotifier.Notifiers.Behaviour

@impl WandererNotifier.Notifiers.Behaviour
def send_message(message, feature \\ nil) do
  # Implementation with new feature parameter
end
```

### Parameter Changes

Some behavior callbacks now include an additional `feature` parameter to specify which feature a notification is related to:

- `send_message/1` -> `send_message/2` (added `feature` parameter)
- `send_embed/4` -> `send_embed/5` (added `feature` parameter)
- `send_file/4` -> `send_file/5` (added `feature` parameter)
- `send_image_embed/4` -> `send_image_embed/5` (added `feature` parameter)

### Added Functions

The behavior now includes a new required function:

- `send_kill_notification/1` - Sends a notification about a killmail

### Maintenance Scheduler

**Previous Usage:**

```elixir
alias WandererNotifier.Maintenance.Scheduler
Scheduler.tick(state)
```

**Current Usage:**

```elixir
alias WandererNotifier.Services.Maintenance.Scheduler
Scheduler.tick(state)
```

### ESI Service Functions

**Previous Usage:**

```elixir
ESIService.get_esi_kill_mail(kill_id, hash, opts)
```

**Current Usage:**

```elixir
ESIService.get_killmail(kill_id, hash)
```

### Feature Function Names

**Previous Usage:**

```elixir
track_all_systems = Features.track_kspace_systems?()
```

**Current Usage:**

```elixir
track_kspace_systems = Features.track_kspace_systems?()
```

## Migration Notes

1. All references to proxy modules have been updated to use the actual implementation modules.
2. All implementations of notifier behavior have been updated to include the new `feature` parameter.
3. An implementation of `send_kill_notification/1` has been added to all notifier implementations.
4. Configuration files have been updated to use the new module names in logging settings.
5. All uses of legacy function names have been standardized to use the current function names.
