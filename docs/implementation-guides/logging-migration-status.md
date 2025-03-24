# Logging Migration Status

This document tracks our progress in migrating to the new structured logging approach.

## Overview of Changes

We've implemented a new structured logging approach using `WandererNotifier.Logger` with these key improvements:

1. **Category-based logging** for better filtering
2. **Structured metadata** for easier analysis
3. **Consistent log levels** across the codebase
4. **JSON formatting** for machine readability
5. **Trace IDs** for request correlation

## Migration Progress

- [x] Created `WandererNotifier.Logger` module
- [x] Created `WandererNotifier.Logger.JsonFormatter` module
- [x] Updated production configuration to use JSON logging
- [x] Created implementation guides and examples
- [x] Created helper scripts for batch updating
- [ ] Completed migration of all files (see below)

## Current Status

Based on the latest scan:

- Total Elixir files: 101
- Already using AppLogger: 72
- Files needing migration: 4 (making great progress!)

## Files Updated

- [x] `lib/wanderer_notifier/resources/tracked_character.ex`
- [x] `lib/wanderer_notifier/notifiers/discord.ex` (partially)
- [x] `lib/wanderer_notifier/services/maintenance.ex`
- [x] `lib/wanderer_notifier/services/maintenance/scheduler.ex`
- [x] `lib/wanderer_notifier/services/notification_determiner.ex`
- [x] `lib/wanderer_notifier/services/character_kills_service.ex`
- [x] `lib/wanderer_notifier/services/system_tracker.ex`
- [x] `lib/wanderer_notifier/api/zkill/websocket.ex`
- [x] `lib/wanderer_notifier/web/controllers/api_controller.ex`
- [x] `lib/wanderer_notifier/chart_service/node_chart_adapter.ex`
- [x] `lib/wanderer_notifier/chart_service/chart_service_manager.ex`
- [x] `lib/wanderer_notifier/chart_service/killmail_chart_adapter.ex`
- [x] `lib/wanderer_notifier/data/cache/repository.ex`
- [x] `lib/wanderer_notifier/discord/notifier.ex`
- [x] `lib/wanderer_notifier/workers/character_sync_worker.ex`

## How to Continue the Migration

### Automated Updates

You can use the helper scripts to automate the basic conversion:

```bash
# Update a single file
./scripts/update_logger.sh lib/wanderer_notifier/some_file.ex category_name

# Run batch updates for whole directories
./scripts/batch_update_logger.sh
```

### Manual Cleanup

After running the automated scripts, you'll need to:

1. Review each file to add structured metadata
2. Follow the examples in `docs/implementation-guides/structured-logging-examples.md`
3. Test the changes to ensure logging works correctly
4. Run the `find_logger_calls.sh` script to verify progress

### Priority Order

Focus on these high-impact files next:

1. ~~`lib/wanderer_notifier/data/cache/repository.ex` (52 calls)~~ - ✅ Completed
2. ~~`lib/wanderer_notifier/services/system_tracker.ex` (49 calls)~~ - ✅ Completed
3. ~~`lib/wanderer_notifier/chart_service/node_chart_adapter.ex` (19 calls)~~ - ✅ Completed
4. ~~`lib/wanderer_notifier/chart_service/chart_service_manager.ex` (22 calls)~~ - ✅ Completed
5. ~~`lib/wanderer_notifier/discord/notifier.ex` (27 calls)~~ - ✅ Completed

## Testing Recommendations

1. **Run in Development Mode**: Test logging output with different levels
2. **Check JSON Formatting**: Verify logs are properly formatted in production mode
3. **Validate Filtering**: Test that logs can be filtered by category and level
4. **Verify Metadata**: Ensure metadata is correctly attached to log entries

## Benefits After Migration

- **Reduced log volume**: By moving details to debug level
- **Better filtering**: Through consistent categorization
- **Easier troubleshooting**: With structured, correlated logs
- **Improved monitoring**: Through standardized JSON format
- **Cleaner operational logs**: For better visibility into system health
