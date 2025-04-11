# Killmail Processing Module Reorganization

## Background

The killmail processing code was previously split across two separate namespaces:

1. `lib/wanderer_notifier/processing/killmail/` - Contains newer implementation modules
2. `lib/wanderer_notifier/killmail_processing/` - Contains core data structures and utility modules

This caused confusion about which modules to use and where new functionality should be added. The reorganization consolidates all killmail-related code under a single unified namespace `WandererNotifier.Killmail`.

## New Structure

```
lib/wanderer_notifier/killmail/
├── core/                   # Core data structures and utilities
│   ├── data.ex             # Renamed from KillmailData
│   ├── context.ex          # Processing context
│   ├── mode.ex             # Processing modes
│   └── validator.ex        # Validation logic
│
├── processing/             # Processing pipeline components
│   ├── processor.ex        # Main entry point (from KillmailProcessor)
│   ├── websocket_processor.ex # Websocket handling (from Processor)
│   ├── api_processor.ex    # API-based processing (from Core)
│   ├── enrichment.ex       # Data enrichment
│   ├── persistence.ex      # Database operations
│   ├── notification.ex     # Notification handling
│   ├── notification_determiner.ex # Notification decision logic
│   └── cache.ex            # Caching logic
│
├── queries/                # Database query functions
│   └── killmail_queries.ex # Database retrieval functions
│
├── metrics/                # Metrics and monitoring
│   ├── metrics.ex          # Metrics collection
│   └── metric_registry.ex  # Metrics registration
│
└── utilities/              # Helper modules
    ├── comparison.ex       # Comparison functionality
    ├── data_access.ex      # Direct data access helpers
    └── transformer.ex      # Data transformation
```

## Completed Migrations

The following modules have been migrated:

### Core

- ✅ `KillmailProcessing.KillmailData` → `Killmail.Core.Data`
- ✅ `KillmailProcessing.Context` → `Killmail.Core.Context`
- ✅ `KillmailProcessing.Mode` → `Killmail.Core.Mode`
- ✅ `KillmailProcessing.Validator` → `Killmail.Core.Validator`

### Processing

- ✅ `Processing.Killmail.KillmailProcessor` → `Killmail.Processing.Processor`
- ✅ `Processing.Killmail.Processor` → `Killmail.Processing.WebsocketProcessor`
- ✅ `Processing.Killmail.ProcessorBehaviour` → `Killmail.Processing.ProcessorBehaviour`

### Behaviours

- ✅ `Processing.Killmail.ProcessorBehaviour` → `Killmail.Processing.ProcessorBehaviour`

## Remaining Migrations

The following modules still need to be migrated:

### Processing

- `Processing.Killmail.Enrichment` → `Killmail.Processing.Enrichment`
- `Processing.Killmail.NotificationDeterminer` → `Killmail.Processing.NotificationDeterminer`
- `Processing.Killmail.Notification` → `Killmail.Processing.Notification`
- `Processing.Killmail.Persistence` → `Killmail.Processing.Persistence`
- `Processing.Killmail.Cache` → `Killmail.Processing.Cache`
- `Processing.Killmail.Core` → `Killmail.Processing.ApiProcessor`
- `Processing.Killmail.PersistenceBehaviour` → `Killmail.Processing.PersistenceBehaviour`

### Utilities

- `Processing.Killmail.Comparison` → `Killmail.Utilities.Comparison`
- `KillmailProcessing.Transformer` → `Killmail.Utilities.Transformer`
- `KillmailProcessing.DataAccess` → `Killmail.Utilities.DataAccess`

### Queries

- `KillmailProcessing.KillmailQueries` → `Killmail.Queries.KillmailQueries`

### Metrics

- `KillmailProcessing.Metrics` → `Killmail.Metrics.Metrics`
- `KillmailProcessing.MetricRegistry` → `Killmail.Metrics.MetricRegistry`

## Migration Process for Remaining Modules

For each module:

1. Create the new file in the appropriate directory
2. Update the module declaration to the new namespace
3. Update all internal references to other modules
4. Add `@deprecated` documentation to the old module
5. Make the old module delegate to the new one

## Using the New Structure

### Example: Processing a Killmail

```elixir
alias WandererNotifier.Killmail.Core.{Context, Data}
alias WandererNotifier.Killmail.Processing.Processor

# Create a processing context
context = Context.new_realtime(character_id, character_name, :zkill_api)

# Process a killmail
case Processor.process_killmail(killmail_data, context) do
  {:ok, result} ->
    # Successfully processed
    Logger.info("Processed killmail #{result.killmail_id}")

  {:ok, :skipped} ->
    # Killmail was skipped
    Logger.info("Skipped killmail processing")

  {:error, reason} ->
    # Error processing killmail
    Logger.error("Failed to process killmail: #{inspect(reason)}")
end
```

### Example: Creating a KillmailData Struct

```elixir
alias WandererNotifier.Killmail.Core.Data

# Create from zKillboard and ESI data
{:ok, killmail_data} = Data.from_zkb_and_esi(zkb_data, esi_data)

# Create from a database resource
killmail_data = Data.from_resource(resource)
```

## Next Steps

1. Complete the migration of all remaining modules
2. Update application code to use the new namespaces
3. Add tests for the new structure
4. After a stable release cycle, remove the deprecated modules

## References

- [Original Refactoring Plan](killmail_pipeline_refactoring_plan.md)
- [PR #XXX: Killmail Module Structure Reorganization](#) (TBD)
