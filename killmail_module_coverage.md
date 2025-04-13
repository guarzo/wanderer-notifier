# Killmail Module Test Coverage

This document maps each migrated module to its test coverage status, helping identify gaps that need to be addressed before removing deprecated modules.

## Core Modules

| Deprecated Module                 | New Module                | Old Tests | New Tests | Gaps | Priority |
| --------------------------------- | ------------------------- | --------- | --------- | ---- | -------- |
| `KillmailProcessing.KillmailData` | `Killmail.Core.Data`      | ✅        | ✅        | None | Low      |
| `KillmailProcessing.Context`      | `Killmail.Core.Context`   | ✅        | ✅        | None | Low      |
| `KillmailProcessing.Mode`         | `Killmail.Core.Mode`      | ✅        | ✅        | None | Low      |
| `KillmailProcessing.Validator`    | `Killmail.Core.Validator` | ✅        | ✅        | None | Low      |

## Processing Modules

| Deprecated Module                            | New Module                                   | Old Tests | New Tests | Gaps                                    | Priority |
| -------------------------------------------- | -------------------------------------------- | --------- | --------- | --------------------------------------- | -------- |
| `Processing.Killmail.KillmailProcessor`      | `Killmail.Processing.Processor`              | ❓        | ✅        | Verify full pipeline                    | High     |
| `Processing.Killmail.Processor`              | `Killmail.Processing.WebsocketProcessor`     | ❓        | ✅        | None                                    | Medium   |
| `Processing.Killmail.ProcessorBehaviour`     | `Killmail.Processing.ProcessorBehaviour`     | ❓        | ❓        | Behaviour tests                         | Low      |
| `Processing.Killmail.Enrichment`             | `Killmail.Processing.Enrichment`             | ❓        | ✅        | None                                    | Medium   |
| `Processing.Killmail.NotificationDeterminer` | `Killmail.Processing.NotificationDeterminer` | ❓        | ✅        | Tests need mock fixes                   | High     |
| `Processing.Killmail.Notification`           | `Killmail.Processing.Notification`           | ❓        | ❓        | Need tests                              | High     |
| `Processing.Killmail.Persistence`            | `Killmail.Processing.Persistence`            | ❓        | ✅        | Tests need mock fixes                   | High     |
| `Processing.Killmail.Cache`                  | `Killmail.Processing.Cache`                  | ❓        | ✅        | Tests need missing KillmailCache module | Medium   |
| `Processing.Killmail.Core`                   | `Killmail.Processing.ApiProcessor`           | ❓        | ✅        | Tests need mock fixes                   | High     |
| `Processing.Killmail.PersistenceBehaviour`   | `Killmail.Processing.PersistenceBehaviour`   | ❓        | ❓        | Behaviour tests                         | Low      |

## Utilities Modules

| Deprecated Module                | New Module                       | Old Tests | New Tests | Gaps       | Priority |
| -------------------------------- | -------------------------------- | --------- | --------- | ---------- | -------- |
| `Processing.Killmail.Comparison` | `Killmail.Utilities.Comparison`  | ❓        | ❓        | Need tests | Medium   |
| `KillmailProcessing.DataAccess`  | `Killmail.Utilities.DataAccess`  | ❓        | ✅        | None       | High     |
| `KillmailProcessing.Transformer` | `Killmail.Utilities.Transformer` | ❓        | ❓        | Need tests | Medium   |

## Queries Modules

| Deprecated Module                    | New Module                         | Old Tests | New Tests | Gaps             | Priority |
| ------------------------------------ | ---------------------------------- | --------- | --------- | ---------------- | -------- |
| `KillmailProcessing.KillmailQueries` | `Killmail.Queries.KillmailQueries` | ✅        | ❓        | Verify migration | Medium   |

## Metrics Modules

| Deprecated Module                   | New Module                        | Old Tests | New Tests | Gaps       | Priority |
| ----------------------------------- | --------------------------------- | --------- | --------- | ---------- | -------- |
| `KillmailProcessing.Metrics`        | `Killmail.Metrics.Metrics`        | ❓        | ❓        | Need tests | Medium   |
| `KillmailProcessing.MetricRegistry` | `Killmail.Metrics.MetricRegistry` | ❓        | ❓        | Need tests | Medium   |

## Next Steps

1. Fix mock issues in tests:
   - Define missing modules like `WandererNotifier.Cache.Killmail`
   - Fix mock setup in test files
2. Implement tests for remaining modules based on priority

## Test Development Plan

### High Priority (In Progress)

1. ✅ Create equivalence tests for `NotificationDeterminer` (test written, needs mock fixes)
2. ✅ Develop tests for `ApiProcessor` (test written, needs mock fixes)
3. ✅ Add tests for `Persistence` (test written, needs mock fixes)
4. ✅ Verify `DataAccess` functionality (working!)

### Medium Priority (In Progress)

1. ✅ Test `Cache` functionality (test written, needs mock fixes)
2. ⏳ Verify `Comparison` operations
3. ⏳ Test `Transformer` with various inputs
4. ⏳ Add tests for `Metrics` and `MetricRegistry`

### Low Priority

1. ⏳ Confirm behaviour implementations
2. ⏳ Review test helpers and utilities

## Progress Updates

- ✅ 2023-11-15: Created equivalence tests for `NotificationDeterminer` (needs mock fixes)
- ✅ 2023-11-15: Added tests for `ApiProcessor` (needs mock fixes)
- ✅ 2023-11-15: Created tests for `Persistence` (needs mock fixes)
- ✅ 2023-11-15: Implemented tests for `DataAccess` (working!)
- ✅ 2023-11-15: Added tests for `Cache` (needs mock fixes)
