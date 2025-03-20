# WandererNotifier Testing Guide

This document provides detailed instructions for testing the notification functionality after the refactoring changes.

## Prerequisites

1. Access to a Discord server with appropriate channels set up
2. Valid and invalid license scenarios available for testing
3. Running development environment for the WandererNotifier
4. Access to zkillboard websocket and API endpoints
5. Access to EVE Map API endpoints

## 1. Kill Notification Testing

### First Message Enhancement Test
1. Start the application with a clean state (no lingering Process dictionary)
2. Trigger a kill notification
3. **Expected Result**: 
   - The first kill notification should be fully enriched with a rich embed
   - It should contain victim details, ship information, and attacker details
   - Confirm in logs: "Sending first kill notification in enriched format (startup message)"

### License Gating Test
1. Set license to invalid state
2. Trigger multiple kill notifications (after first one)
3. **Expected Result**:
   - Only the first kill notification should be enriched
   - Subsequent notifications should be basic text messages
4. Set license to valid state  
5. Trigger additional kill notifications
6. **Expected Result**:
   - All notifications should now be rich embeds

### Data Fallback Test
1. Send a kill notification with incomplete victim data (missing corporation)
2. **Expected Result**:
   - System should attempt to lookup corporation name from ESI
   - If ESI fails, it should use a fallback value
   - Check logs to confirm ESI lookup behavior

### zkillboard Link Test
1. Click on the zkillboard links in a kill notification
2. **Expected Result**:
   - Links should go to the correct zkillboard pages for the kill, character, etc.

## 2. Character Notification Testing

### First Character Notification Test
1. Restart the application
2. Trigger a character notification for a tracked character
3. **Expected Result**:
   - The first character notification should be fully enriched regardless of license
   - It should show character name, portrait, and corporation details 
   - Confirm in logs: "Sending first character notification in enriched format (startup message)"

### Corporation Name Extraction Test
1. Trigger notifications for characters with and without corporation information
2. **Expected Result**:
   - Character with corporation: Corporation name displayed correctly
   - Character without corporation: Appropriate fallback displayed
   - Character with just ticker: Ticker displayed in square brackets

### Portrait Image Test
1. Check the character portrait in the notification
2. **Expected Result**:
   - Image should properly load from EVE image server
   - URL format should be correct: `https://imageserver.eveonline.com/Character/[id]_128.jpg`

## 3. System Notification Testing

### First System Notification Test
1. Restart the application
2. Add a system to tracking
3. **Expected Result**:
   - First system notification should be enriched regardless of license status
   - Confirm in logs: "Sending first system notification in enriched format (startup message)"

### System Type Test
Test with multiple system types:
1. Highsec system
2. Lowsec system
3. Nullsec system
4. Wormhole system (with class information)

**Expected Results**:
- Each system should have appropriate type description
- The notification color should match the security status (green, yellow, red, blue)
- Wormhole systems should include effect information when available
- K-space systems should show region information

### Static Information Test
1. Test notifications for wormhole systems with statics
2. **Expected Result**:
   - Static wormhole types should be listed in the notification
   - For shattered wormholes, the "Shattered" attribute should be visible

### Region Information Test
1. Test notifications for systems in various regions
2. **Expected Result**:
   - Region name should be correctly displayed
   - Region name should be a clickable link to dotlan

## 4. WebSocket Functionality Testing

### Connection Monitoring Test
1. Start the application and check connection status
2. **Expected Result**:
   - WebSocket connects successfully to zkillboard
   - Status information is updated in logs and stats

### Reconnection Test
1. Temporarily disable network connectivity
2. Wait for automatic reconnection attempts
3. Restore network connectivity
4. **Expected Result**:
   - WebSocket should attempt to reconnect
   - Logs should show reconnection attempts
   - After network restoration, WebSocket should reconnect

### Message Flow Test
1. Ensure zkillboard is sending kill messages
2. Monitor the system for incoming messages
3. **Expected Result**:
   - Kill messages should be received from zkillboard
   - Messages should be processed and trigger notifications
   - Logs should show message transmission through the system

### Circuit Breaker Test
1. Create conditions for frequent disconnections
2. **Expected Result**:
   - After reaching disconnection threshold, circuit breaker should engage
   - Logs should show: "Circuit breaker engaged after X disconnects in Y seconds"
   - Reconnection should be delayed using exponential backoff

## 5. General Testing

### License Validation Test
1. Test with valid license:
   - Ensure all notification types are enriched
2. Test with invalid license:
   - Only first notification of each type should be enriched
   - Subsequent notifications should be simple text
3. Change license during runtime:
   - Behavior should change accordingly without restart

### Error Handling Test
1. Test with intentionally malformed data
2. **Expected Result**:
   - System should handle errors gracefully
   - Appropriate fallback values should be used
   - Logs should show meaningful error messages

### Startup Behavior Test
1. Restart the application multiple times
2. **Expected Result**:
   - WebSocket should connect reliably
   - First notification flags should reset properly
   - Application should initialize correctly without errors

## Reporting Test Results

When testing, please note:
1. Any unexpected behavior or discrepancies
2. Performance issues or delays
3. Error messages or exceptions
4. Specific test cases that failed or succeeded
5. Log snippets that illuminate system behavior


---------

Test Results


- does not appear websocket is receiving kills -- may need to adjust logging to troubleshoot
13:39:02.739 [info] Connected to zKill websocket.
13:39:02.739 [info] Successfully initialized zKillboard WebSocket with PID: #PID<0.322.0>
13:39:02.739 [info] ZKill websocket started: #PID<0.322.0>

- test kill notification with no kills (license is valid)
13:39:26.943 [info] GET /api/test-notification
13:39:26.944 [info] Test notification endpoint called
13:39:26.947 [info] Sending test kill notification...
13:39:26.947 [info] No recent kills available, using sample test data
13:39:27.631 [info] Sending first kill notification in enriched format (startup message)
13:39:27.635 [info] Sending Discord embed to URL: https://discord.com/api/channels/971101320138350603/messages for feature: :kill_notifications
13:39:27.929 [info] Successfully sent Discord embed, status: 200
13:39:27.929 [info] Sent 200 in 985ms

CCP Garthagk (C C P Alliance)
Kill Notification
CCP Garthagk lost a Capsule in Unknown System
Value
150M ISK
Attackers
1
Final Blow
CCP Zoetrope (Avatar)
Alliance
C C P Alliance
Image
Kill ID: 12345678•5/1/2023 8:00 AM

-- system notification, valid license
13:41:09.393 [info] GET /api/test-system-notification
13:41:09.393 [info] Test system notification endpoint called
13:41:09.393 [info] TEST NOTIFICATION: Manually triggering a test system notification
13:41:09.393 [info] Found 19 tracked systems
13:41:09.393 [info] Using system J000001 (ID: 31000001) for test notification
13:41:09.394 [info] Sending first system notification in enriched format (startup message)
13:41:09.394 [info] [Discord.send_system_activity] Sending recent system activity: System ID 31000914
13:41:09.400 [info] [ZKill] Requesting system kills for 31000914 (limit: 5)
13:41:10.543 [info] [ZKill] Successfully parsed 5 kills for system 31000914
13:41:10.543 [info] Found 5 recent kills for system 31000914 from zKillboard
13:41:13.486 [info] Sending Discord embed to URL: https://discord.com/api/channels/971101320138350603/messages for feature: :system_tracking
13:41:13.706 [info] Successfully sent Discord embed, status: 200
13:41:13.706 [info] Sent 200 in 4312ms

New Wormhole System Mapped
A Wormhole system has been discovered and added to the map.
System
131 (J112850)
Recent Kills in System
Alfred Johnson - Imicus - 15M ISK (59m ago)
tomasxp232 Boirelle - Capsule - 10k ISK (2d ago)
tomasxp232 Boirelle - Heron - 2M ISK (2d ago)
rek67rus - Capsule - 10k ISK (18d ago)
rek67rus - Brutix Navy Issue - 244M ISK (18d ago)
Image
Today at 9:41 AM

appears to be missing static information, otherwise looks correct


- character notification
13:42:03.197 [info] GET /api/test-character-notification
13:42:03.197 [info] Test character notification endpoint called
13:42:03.197 [info] TEST NOTIFICATION: Manually triggering a test character notification
13:42:03.198 [info] Found 134 tracked characters
13:42:03.201 [info] Using character Roy G Orlenard (ID: 2114822138) for test notification
13:42:03.343 [info] Sending first character notification in enriched format (startup message)
13:42:03.343 [info] Sending Discord embed to URL: https://discord.com/api/channels/971101320138350603/messages for feature: :character_tracking
13:42:03.558 [info] Successfully sent Discord embed, status: 200
13:42:03.558 [info] Sent 200 in 361ms
New Character Tracked
A new character has been added to the tracking list.
Character
Roy G Orlenard
Corporation
NRXN
Image
Today at 9:42 AM

notification matches specification, but we should make the corpration name/ticker into a link to the zkillboard for the corporation


- invalid license testing 

we don't seem to be tracking if we've send the first message? mayube just an issue with test notifications??
13:44:02.313 [info] Successfully sent Discord embed, status: 200
13:44:02.313 [info] Sent 200 in 496ms
13:44:13.275 [info] GET /api/test-notification
13:44:13.275 [info] Test notification endpoint called
13:44:13.275 [info] Sending test kill notification...
13:44:13.275 [info] No recent kills available, using sample test data
13:44:13.564 [info] Sending first kill notification in enriched format (startup message)
13:44:13.564 [info] Sending Discord embed to URL: https://discord.com/api/channels/971101320138350603/messages for feature: :kill_notifications
13:44:13.706 [info] Successfully sent Discord embed, status: 200
13:44:13.706 [info] Sent 200 in 431ms
13:44:13.832 [info] GET /api/test-notification
13:44:13.833 [info] Test notification endpoint called
13:44:13.833 [info] Sending test kill notification...
13:44:13.833 [info] No recent kills available, using sample test data
13:44:14.098 [info] Sending first kill notification in enriched format (startup message)
13:44:14.098 [info] Sending Discord embed to URL: https://discord.com/api/channels/971101320138350603/messages for feature: :kill_notifications
13:44:14.248 [info] Successfully sent Discord embed, status: 200
13:44:14.248 [info] Sent 200 in 415ms
13:44:14.521 [info] GET /api/test-notification
13:44:14.521 [info] Test notification endpoint called
13:44:14.522 [info] Sending test kill notification...
13:44:14.522 [info] No recent kills available, using sample test data
13:44:14.781 [info] Sending first kill notification in enriched format (startup message)
13:44:14.781 [info] Sending Discord embed to URL: https://discord.com/api/channels/971101320138350603/messages for feature: :kill_notifications
13:44:15.009 [info] Successfully sent Discord embed, status: 200
13:44:15.009 [info] Sent 200 in 487ms


-- other comment
we should send a more detailed message a startup, a nicely formatted embedded message including the features enabled -- and the post-start systems/characters trackedup



---- New Test Results ---

compilation warnings

elixir ➜ /workspaces/wanderer-notifier (guarzo/notif) $ make s
Compiling 85 files (.ex)
     warning: variable "fields" is unused (there is a variable with the same name in the context, use the pin operator (^) to match on it or prefix this variable with underscore if it is not meant to be used)
     │
 137 │     fields = fields ++ [%{name: "Enabled Features", value: enabled_features, inline: false}]
     │     ~~~~~~
     │
     └─ lib/wanderer_notifier/application.ex:137:5: WandererNotifier.Application.send_startup_message/0

     warning: WandererNotifier.Core.Config.system_tracking_enabled?/0 is undefined or private. Did you mean:

           * system_notifications_enabled?/0

     │
 257 │       system_tracking_enabled: WandererNotifier.Core.Config.system_tracking_enabled?(),
     │                                                             ~
     │
     └─ lib/wanderer_notifier/core/features.ex:257:61: WandererNotifier.Core.Features.get_feature_status/0

Generated wanderer_notifier app
Building frontend assets...


// startup log
14:24:41.893 [error] Task #PID<0.460.0> started from #PID<0.303.0> terminating
** (KeyError) key :premium not found in: %{
  error: :invalid_license,
  valid: false,
  details: %{
    "bot_associated" => false,
    "bot_id" => "6b939604-7799-4df9-91a9-07a779382aa5",
    "bot_name" => "Wanderer Notifier",
    "bots" => [],
    "license_valid" => false,
    "message" => "License not found",
    "valid" => false
  },
  bot_assigned: false,
  error_message: "License not found",
  last_validated: 1742480678
}
    (wanderer_notifier 0.1.0) lib/wanderer_notifier/application.ex:104: WandererNotifier.Application.send_startup_message/0
    (elixir 1.18.2) lib/task/supervised.ex:101: Task.Supervised.invoke_mfa/2
Function: #Function<4.81436476/0 in WandererNotifier.Application.start/2>
    Args: []

// kill notification testing
WandererNotifier Service started. Listening for notifications.

CCP Garthagk (C C P Alliance)
Kill Notification
CCP Garthagk lost a Capsule in Unknown System
Value
150M ISK
Attackers
1
Final Blow
CCP Zoetrope (Avatar)
Alliance
C C P Alliance
Image
Kill ID: 12345678•5/1/2023 8:00 AM
Kill Alert: CCP Garthagk lost a Capsule in Unknown System.

notifications look correct, first is embedded, send is plain test (license is currently invalid)

// system notification (invalid license)
New Wormhole System Mapped
A Wormhole system has been discovered and added to the map.
System
112 (J142653)
Recent Kills in System
Ositha Greyfax 2 - Sigil - 7M ISK (1d ago)
Este the Noldor - Capsule - 10k ISK (1d ago)
Enrico vonKastell - Guardian - 1638M ISK (1d ago)
Warthog A-10 - Capsule - 10k ISK (1d ago)
Este the Noldor - Tempest - 447M ISK (1d ago)
Image
Today at 10:27 AM
New System Discovered: Unknown System - Wormhole

we seem to have not updated the embedded message to include the static information, and the plain text message needs to include the temporary name ( original name), not just "wormhole"

// character testing  (invalid license)

New Character Tracked
A new character has been added to the tracking list.
Character
Smosh Cringe
Corporation
ABSOD
Image
Today at 10:28 AM
New Character Tracked: Eti One (Hidden Asset Authority)

we clearly have the corporation id if we're able to get the ticker, why aren't we able to provide the corporation name and the  zkilboard link?



