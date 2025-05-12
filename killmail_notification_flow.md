# Killmail Notification Flow

This document traces the complete path of a killmail from initial receipt to final notification.

## 1. Initial Receipt and Processing

### Entry Point

- **Function**: `process_zkill_message/2`
- **File**: `lib/wanderer_notifier/killmail/processor.ex`
- **Description**: Receives raw JSON message from ZKillboard websocket and begins processing

### Initial Notification Determination

- **Function**: `determine_notification/1`
- **File**: `lib/wanderer_notifier/killmail/processor.ex`
- **Description**: Makes first determination if the killmail should be processed
- **Calls**: `WandererNotifier.Notifications.Determiner.Kill.should_notify?/1`

### Killmail Tracking Check (Inside should_notify?)

- **Function**: `check_tracking/2`
- **File**: `lib/wanderer_notifier/notifications/determiner/kill.ex`
- **Description**: Checks if the system or any characters are tracked

### If Should Notify, Process the Killmail

- **Function**: `process_kill_data/2`
- **File**: `lib/wanderer_notifier/killmail/processor.ex`
- **Description**: Processes the killmail data that passed initial checks

## 2. Killmail Pipeline

### Pipeline Entry Point

- **Function**: `process_killmail/2`
- **File**: `lib/wanderer_notifier/killmail/pipeline.ex`
- **Description**: Central processing function for killmails

### Killmail Creation

- **Function**: `create_killmail/1`
- **File**: `lib/wanderer_notifier/killmail/pipeline.ex`
- **Description**: Creates Killmail struct with data from ZKB and ESI

### Killmail Enrichment

- **Function**: `enrich_killmail/1`
- **File**: `lib/wanderer_notifier/killmail/pipeline.ex`
- **Description**: Enriches killmail with additional data
- **Calls**: `WandererNotifier.Killmail.Enrichment.enrich_killmail_data/1`

### Pipeline Tracking Check (Now Bypassed)

- **Function**: `check_tracking/1`
- **File**: `lib/wanderer_notifier/killmail/pipeline.ex`
- **Description**: Previously did duplicate tracking check, now passes killmail through

### Notification Determination

- **Function**: `check_notification/2`
- **File**: `lib/wanderer_notifier/killmail/pipeline.ex`
- **Description**: Second determination of whether killmail should trigger notification
- **Calls**: `WandererNotifier.Notifications.Determiner.Kill.should_notify?/1`
- **Issue**: This function is also redundant and should be simplified to pass through like `check_tracking`

### Sending Notification Decision

- **Function**: `maybe_send_notification/3`
- **File**: `lib/wanderer_notifier/killmail/pipeline.ex`
- **Description**: Decides whether to send the notification based on previous checks
- **Calls**: `WandererNotifier.Killmail.Notification.send_kill_notification/2`

## 3. Notification Creation and Sending

### Notification Service Entry

- **Function**: `send_kill_notification/3`
- **File**: `lib/wanderer_notifier/notifications/killmail_notification.ex`
- **Description**: Creates and sends notification for a killmail
- **Key Checks**: Checks `tracked_system?` and `has_tracked_character?` again

### Notification Creation

- **Function**: `create_notification/3`
- **File**: `lib/wanderer_notifier/notifications/killmail_notification.ex`
- **Description**: Creates a notification object with killmail data

### Notification Service

- **Function**: `send/1`
- **File**: `lib/wanderer_notifier/notifications/notification_service.ex`
- **Description**: Processes and standardizes notification data

### Notification Dispatch

- **Function**: `send_message/1`
- **File**: `lib/wanderer_notifier/notifications/factory.ex`
- **Description**: Routes notification to appropriate handler
- **Note**: This is the WandererNotifier.Notifications.Dispatcher module

### Notification Type Handling

- **Function**: `handle_notification_by_type/1` and `handle_kill_notification/1`
- **File**: `lib/wanderer_notifier/notifications/factory.ex`
- **Description**: Processes notification based on its type

### Discord Notification

- **Function**: `dispatch_kill_notification/2`
- **File**: `lib/wanderer_notifier/notifications/factory.ex`
- **Description**: Dispatches kill notification to Discord notifier

## 4. Discord Delivery

### Discord Kill Notification

- **Function**: `send_kill_notification/1`
- **File**: `lib/wanderer_notifier/notifiers/discord/notifier.ex`
- **Description**: Formats and prepares killmail notification for Discord

### Formatted Kill Notification

- **Function**: `send_killmail_notification/1`
- **File**: `lib/wanderer_notifier/notifiers/discord/notifier.ex`
- **Description**: Formats the killmail notification for Discord

### Discord Send

- **Function**: `send_to_discord/2`
- **File**: `lib/wanderer_notifier/notifiers/discord/notifier.ex`
- **Description**: Sends the formatted notification to Discord

### Final Discord API Call

- **Function**: `send_embed/2` or `send_message_with_components/3`
- **File**: `lib/wanderer_notifier/notifiers/discord/neo_client.ex`
- **Description**: Makes the actual API call to Discord's servers

## Key Issues Identified

1. **Redundant Tracking Checks**: The system was checking the same tracking conditions multiple times
2. **Pipeline Overriding Initial Decision**: Even though killmails passed initial validation, they were being re-checked and potentially rejected in the pipeline
3. **Resolution**: Modified `check_tracking/1` in pipeline to bypass duplicate validation, ensuring killmails that passed initial validation would continue through the entire flow

## Technical Debt & Improvement Areas

1. Consolidate tracking logic into a single location to avoid duplication
2. Add more comprehensive logging throughout the flow
3. Consider adding metrics to track where killmails are being dropped from the pipeline

## Remaining Tasks to Fix Kill Notifications

1. **Fix check_notification in Pipeline**: Similar to the `check_tracking` function, the `check_notification` function in pipeline.ex still duplicates the initial check and should be simplified to pass through killmails.

2. **Fix KillmailNotification Module**: In `lib/wanderer_notifier/notifications/killmail_notification.ex`, the `send_kill_notification` function also rechecks tracking conditions with:
   ```elixir
   tracked_system_result = KillDeterminer.tracked_system?(system_id),
   tracked_character_result = KillDeterminer.has_tracked_character?(enriched_killmail),
   ```
   This introduces yet another place where a killmail that passed the initial check might be rejected.
3. **Refactor Notification Flow**: Consider refactoring to ensure notification determination happens only once at the very beginning of the process, with all subsequent steps trusting that determination.

4. **Add Comprehensive Instrumentation**: Add detailed metrics to track the rate of killmails at each stage of the pipeline to quickly identify future issues.

5. **Refactor Determiner.Kill.should_notify?**: This central function has too many responsibilities. Consider breaking it down into smaller, more focused functions.
