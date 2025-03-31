# Proxy Module Dependency Graph

## NotifierBehaviour Dependencies

```
WandererNotifier.NotifierBehaviour
├── Implements: WandererNotifier.Discord.Notifier
│   └── Used by: Multiple modules in the application for sending notifications
├── Implements: WandererNotifier.Discord.TestNotifier
│   └── Used in test environment
└── Implements: WandererNotifier.Notifiers.TestNotifier
    └── Used in test environment
```

The target module `WandererNotifier.Notifiers.Behaviour` is already implemented by `WandererNotifier.Notifiers.Discord.Test`.

## Maintenance.Scheduler Dependencies

```
WandererNotifier.Maintenance.Scheduler
└── Used by: WandererNotifier.Services.Maintenance
    └── Started by: WandererNotifier.Application
```

The target module `WandererNotifier.Services.Maintenance.Scheduler` is only used through the proxy module.

## get_esi_kill_mail Dependencies

```
WandererNotifier.Api.ESI.Service.get_esi_kill_mail/3
└── Used by: WandererNotifier.Api.ZKill.Service
```

The target function `get_killmail/2` is already used directly in other parts of the application.

## track_all_systems? Dependencies

```
Features.track_kspace_systems? (new name)
├── Used by: WandererNotifier.Api.Map.SystemsClient
├── Used by: WandererNotifier.Services.NotificationDeterminer
└── Indirectly used by other modules through these services

track_all_systems? (old name)
└── Used by: WandererNotifier.Api.Map.Systems
```

## Test Dependencies

### NotifierBehaviour

No test mocks were found that directly reference `WandererNotifier.NotifierBehaviour`, but there are two test notifier implementations:

1. `WandererNotifier.Discord.TestNotifier`
2. `WandererNotifier.Notifiers.TestNotifier`

### Maintenance.Scheduler

No test mocks were found that directly reference `WandererNotifier.Maintenance.Scheduler`.

### ESI Service

There may be test mocks for `get_esi_kill_mail` in test modules, but none were directly identified during this audit.

## Potential Migration Issues

1. **NotifierBehaviour Parameter Mismatch**: The `feature` parameter exists in the target module's functions but not in the proxy. Implementations need to be updated to support this parameter.

2. **Missing Callback Functions**: The `send_kill_notification/1` callback exists in the target but not in the proxy. Implementations need to add this function.

3. **Extra Functions**: `send_kill_embed/2` exists in the proxy but not in the target. A solution needs to be determined for this function.

4. **Environment Variables**: Both old and new names for system tracking are supported in environment variables. These need to be standardized.
