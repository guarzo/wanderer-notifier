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
- ✅ `Processing.Killmail.Enrichment` → `Killmail.Processing.Enrichment`
- ✅ `Processing.Killmail.NotificationDeterminer` → `Killmail.Processing.NotificationDeterminer`
- ✅ `Processing.Killmail.Notification` → `Killmail.Processing.Notification`
- ✅ `Processing.Killmail.Persistence` → `Killmail.Processing.Persistence`
- ✅ `Processing.Killmail.Cache` → `Killmail.Processing.Cache`
- ✅ `Processing.Killmail.Core` → `Killmail.Processing.ApiProcessor`
- ✅ `Processing.Killmail.Comparison` → `Killmail.Utilities.Comparison`

### Queries

- ✅ `KillmailProcessing.KillmailQueries` → `Killmail.Queries.KillmailQueries`

### Utilities

- ✅ `KillmailProcessing.DataAccess` → `Killmail.Utilities.DataAccess`
- ✅ `KillmailProcessing.Transformer` → `Killmail.Utilities.Transformer`

### Metrics

- ✅ `KillmailProcessing.Metrics` → `Killmail.Metrics.Metrics`
- ✅ `KillmailProcessing.MetricRegistry` → `Killmail.Metrics.MetricRegistry`

### Behaviours

- ✅ `Processing.Killmail.ProcessorBehaviour` → `Killmail.Processing.ProcessorBehaviour`
- ✅ `Processing.Killmail.PersistenceBehaviour` → `Killmail.Processing.PersistenceBehaviour`

## Status of Current Migrations

All the modules have been successfully migrated! Each module has been updated to:

1. Create the new module in the appropriate directory
2. Add proper implementation in the new namespace
3. Add `@deprecated` documentation to the old modules
4. Update the old modules to delegate to the new ones

The application has also been updated to use the new module locations, particularly in the application.ex file.

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

1. ✅ Complete the migration of remaining modules
2. ✓ Update application code to use the new namespaces
3. □ Run comprehensive tests to ensure all functionality works correctly
4. □ After a stable release cycle, remove the deprecated modules

## References

- [Original Refactoring Plan](killmail_pipeline_refactoring_plan.md)
