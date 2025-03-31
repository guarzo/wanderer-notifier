# Proxy Module Audit

## WandererNotifier.NotifierBehaviour

**Path**: `lib/wanderer_notifier/notifier_behaviour.ex`

**Description**: Proxy module that forwards to `WandererNotifier.Notifiers.Behaviour`. Defines the common interface that all notifier implementations must implement.

**Target Module**: `WandererNotifier.Notifiers.Behaviour` at `lib/wanderer_notifier/notifiers/behaviour.ex`

**Key Differences**:

- The target module `Behaviour` adds a `feature` parameter to several methods that is not present in the proxy
- The target module has an additional callback `send_kill_notification/1` not in the proxy module
- The proxy includes `send_kill_embed/2` which is not present in the target module

**Callback Functions**:

1. `send_message/1`
2. `send_embed/4`
3. `send_file/4`
4. `send_new_tracked_character_notification/1`
5. `send_new_system_notification/1`
6. `send_enriched_kill_embed/2`
7. `send_image_embed/4`
8. `send_kill_embed/2`

**Implementations**:

1. `WandererNotifier.Discord.Notifier` - Main implementation for Discord notifications
2. `WandererNotifier.Discord.TestNotifier` - Test implementation for Discord
3. `WandererNotifier.Notifiers.TestNotifier` - General test implementation

**Usage Locations**:

- `lib/wanderer_notifier/discord/notifier.ex`: 8 occurrences (@behaviour + 7 @impl annotations)
- `lib/wanderer_notifier/discord/test_notifier.ex`: 8 occurrences (@behaviour + 7 @impl annotations)
- `lib/wanderer_notifier/notifiers/test_notifier.ex`: 9 occurrences (@behaviour + 8 @impl annotations)

## WandererNotifier.Maintenance.Scheduler

**Path**: `lib/wanderer_notifier/maintenance/scheduler.ex`

**Description**: Proxy module that delegates to the Services.Maintenance.Scheduler module. Handles scheduling and execution of maintenance tasks.

**Target Module**: `WandererNotifier.Services.Maintenance.Scheduler` at `lib/wanderer_notifier/services/maintenance/scheduler.ex`

**Functions**:

1. `tick/1` - Performs periodic maintenance tasks
2. `do_initial_checks/1` - Performs initial checks when the service starts

**Usage Locations**:

- `lib/wanderer_notifier/services/maintenance.ex`: Primary usage - system calls the Scheduler for maintenance tasks
- `config/config.exs` and `config/prod.exs`: Logger configuration settings

## Legacy ESI Service Function

**Path**: `lib/wanderer_notifier/api/esi/service.ex`

**Function**: `get_esi_kill_mail/3`

**Description**: Legacy function that delegates to `get_killmail/2` for backward compatibility

**Target Function**: `get_killmail/2` in the same module

**Key Differences**:

- The legacy function includes an optional `_opts` parameter that is not used
- The legacy function logs that it's using the legacy method before delegating

**Usage Locations**:

- `lib/wanderer_notifier/api/zkill/service.ex`: Only external usage found

## Deprecated Feature Functions

**Feature Function**: `track_all_systems?`

**Current Replacement**: `track_kspace_systems?`

**Modules Using Replacement**:

- `lib/wanderer_notifier/config/features.ex`: Main implementation
- `lib/wanderer_notifier/config/system_tracking.ex`: Alternative implementation
- `lib/wanderer_notifier/api/map/systems.ex:148`: Uses the function with legacy naming
- `lib/wanderer_notifier/api/map/systems_client.ex:130`: Uses the modern function name

**Environment Configuration**:

- `config/runtime.exs`: Has support for both function names via environment variables
