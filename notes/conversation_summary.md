# Conversation Summary

## 2024-03-20: Scheduler Validation

Completed a thorough validation of all scheduled tasks in the WandererNotifier application:

1. **Created scheduler validation documentation** - Created a comprehensive markdown document at `notes/scheduler_validation.md` that documents all scheduled tasks, their behavior, timing, and validation status.

2. **Validated four main schedulers**:

   - TPS Chart Scheduler (time-based, runs daily at 12:00 UTC)
   - Activity Chart Scheduler (interval-based, runs every 24 hours)
   - Character Update Scheduler (interval-based, runs every 30 minutes)
   - System Update Scheduler (interval-based, runs every 60 minutes)

3. **Documented scheduler architecture** - Outlined the well-structured scheduler system including BaseScheduler, IntervalScheduler, TimeScheduler, Factory, Registry, and Supervisor.

4. **Verified timing configurations** - Confirmed that all schedulers use timing values from the centralized `WandererNotifier.Core.Config.Timings` module.

5. **Made recommendations** for future improvements including more comprehensive error handling, retry logic for API failures, telemetry for scheduler execution, and a web dashboard for monitoring.

The task is now marked as completed in the task list. Next priority tasks include creating an enhanced startup message and migrating from QuickCharts to the node chart service.

## 2024-03-20: Killmail Notification Logic Documentation

Documented the killmail notification system in the WandererNotifier application:

1. **Created killmail notification documentation** - Created a comprehensive markdown document at `notes/killmail_notification_logic.md` that outlines the full killmail notification flow from the zKillboard WebSocket to Discord delivery.

2. **Mapped the killmail data flow**:

   - WebSocket Connection (ZKill.Websocket)
   - Message Processing (Service)
   - Killmail Handling (KillProcessor)
   - Data Structure (Killmail)
   - Enrichment (Discord.Notifier)
   - Notification Formatting (StructuredFormatter)
   - Discord Delivery (Discord.Notifier)

3. **Identified key components** - Documented all the major components involved in killmail processing including their file locations and responsibilities.

4. **Outlined enrichment process** - Detailed how killmail data is enriched with system, character, and ship information.

5. **Added troubleshooting points** - Included guidance for common issues that might occur with killmail notifications.

This documentation will help with troubleshooting current killmail notification issues and provide a reference for any future refactoring.

## 2024-03-22: Restored and Improved Kill Notification Filtering

Restored and enhanced the killmail notification filtering system that was lost in a previous refactor:

1. **Created centralized notification determiner** - Implemented a new module `WandererNotifier.Services.NotificationDeterminer` to centralize all notification filtering logic.

2. **Restored proper notification criteria**:

   - Notifications are now properly filtered based on:
     - Global feature flag (`kill_notifications_enabled?`)
     - Whether the kill occurred in a tracked system
     - Whether the kill involved a tracked character (as victim or attacker)
   - A notification is sent only if either the system or character criteria is met

3. **Improved code organization**:

   - Moved duplicated filtering logic from `KillProcessor` to the new module
   - Updated the workflow to use the centralized notification determiner
   - Added detailed logging to track notification decisions

4. **Updated documentation** - Enhanced the killmail notification documentation to reflect the new filtering logic and workflow.

5. **Created PR description** - Prepared a detailed PR description in `notes/pr_description.md` explaining all changes and improvements.

The kill notification system now properly filters notifications based on tracked systems and characters, which was the original design intention before it was lost in a previous refactor. The code is also better organized with centralized logic for improved maintainability.

## 2023-12-24

### Task 1: Verify scheduler validation logic for tracking systems

The task involved checking how the scheduler's validation logic works for tracking systems, with a focus on solar system IDs. After examining the code, it was confirmed that the validation happens in the `add_item/2` function in the `WandererNotifier.Core.Scheduler` module, which executes before any item is inserted into the database. The validation includes checks for whether the system exists in the game universe and if the player has the required license to track it.

### Task 2: Document killmail notification logic

A new document was created to explain how the killmail notification system works, detailing the flow from receiving webhooks to sending notifications. The document outlines the components involved, the processing steps, and how the system determines which notifications to send.

### Task 3: Restore notification filtering criteria

Restored the proper notification filtering criteria that were lost during a previous refactor. The updated system now properly checks if a kill occurred in a tracked system or involved a tracked character (as victim or attacker) before sending a notification.

### Task 4: Create centralized notification determiner

Created a new module called `WandererNotifier.Services.NotificationDeterminer` that centralizes all notification determination logic. This module provides functions to check if kills, systems, and characters should trigger notifications based on specified criteria. The module includes:

- `should_notify_kill?/2` - Determines if a killmail should trigger a notification
- `is_tracked_system?/1` - Checks if a system is being tracked
- `has_tracked_character?/1` - Checks if a killmail involves a tracked character
- `should_notify_system?/1` - Determines if a system should trigger a notification
- `should_notify_character?/1` - Determines if a character should trigger a notification

### Task 5: Update existing code to use centralized notification logic

Refactored the following components to use the centralized notification determiner:

1. Kill Processor

   - Updated `should_send_notification?` function to use `NotificationDeterminer.should_notify_kill?`
   - Improved error logging and handling

2. System Notifications

   - Updated `notify_new_systems` in `Api.Map.Systems` to use `NotificationDeterminer.should_notify_system?`
   - Added checks for both global system notifications and individual system notifications

3. Character Notifications
   - Updated `notify_new_tracked_characters` in `Api.Map.Characters` to use `NotificationDeterminer.should_notify_character?`
   - Added checks for both global character notifications and individual character notifications

### Task 6: Update documentation

Updated the killmail notification logic documentation to reflect the changes and created a comprehensive PR description detailing all the improvements made to the notification system.
