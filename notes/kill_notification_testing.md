# Kill Notification Testing Guide

This document provides a step-by-step guide to test kill notifications in WandererNotifier after the recent refactoring.

## Prerequisites

1. Running instance of WandererNotifier
2. Discord webhook setup correctly in environment variables
3. Access to the application logs

## Environment Setup

For testing kill notifications, set the following environment variables:

```bash
# Enable kill notifications
export ENABLE_KILL_NOTIFICATIONS=true

# Process kills from all systems, not just wormholes (for testing)
export PROCESS_ALL_KILLS=true

# Optional: Set a specific Discord channel for kill notifications
# export DISCORD_KILL_CHANNEL_ID=123456789012345678
```

## Testing Procedure

### 1. Testing First Kill Notification Enhancement

**Objective**: Verify that the first kill notification after startup is always enriched, regardless of license status.

**Steps**:
1. Stop the WandererNotifier application if running
2. Clear any existing application state
3. Set license to INVALID status (for testing the first-message enhancement)
4. Start the application
5. Trigger a test kill notification using the API endpoint

```bash
# Create a test notification via API
curl -X POST http://localhost:4000/api/test/kill_notification
```

**Expected Results**:
- The first kill notification should be a rich embed with full details
- The application logs should show: "Sending first kill notification in enriched format (startup message)"
- The Process dictionary flag `:first_kill_notification` should be set to `false` after the first notification

### 2. Testing License Gating

**Objective**: Verify that only the first notification is enriched when license is invalid.

**Steps**:
1. Ensure license is still INVALID
2. Trigger multiple additional kill notifications

```bash
# Create more test notifications
curl -X POST http://localhost:4000/api/test/kill_notification
curl -X POST http://localhost:4000/api/test/kill_notification
```

**Expected Results**:
- Only the first notification should be a rich embed
- Subsequent notifications should be basic text notifications
- Logs should confirm this behavior

### 3. Testing with Valid License

**Objective**: Verify that all notifications are enriched with a valid license.

**Steps**:
1. Change license to VALID status
2. Trigger multiple kill notifications

```bash
# Create more test notifications with valid license
curl -X POST http://localhost:4000/api/test/kill_notification
curl -X POST http://localhost:4000/api/test/kill_notification
```

**Expected Results**:
- All notifications should be rich embeds with full details
- Logs should confirm that notifications are being sent in enriched format

### 4. Testing Data Enrichment and Fallbacks

**Objective**: Verify that the system properly enriches kill data and uses fallbacks when needed.

**Steps**:
1. Trigger a kill notification with incomplete data
2. Check how the system handles missing fields

**Expected Results**:
- System should attempt to fetch missing data from ESI
- If data cannot be found, appropriate fallbacks should be used
- Logs should show ESI lookup attempts and fallbacks

### 5. Testing WebSocket Connection

**Objective**: Verify that the WebSocket connection to zKillboard is working correctly.

**Steps**:
1. Check WebSocket connection status
2. Observe any incoming kill messages
3. Verify that real-time kill notifications are processed

```bash
# Check WebSocket status via API
curl http://localhost:4000/api/status
```

**Expected Results**:
- WebSocket should be connected to zKillboard
- Status should show connection information
- Logs should show WebSocket activity

### 6. Testing Reconnection Logic

**Objective**: Verify that the WebSocket reconnection logic works properly.

**Steps**:
1. Temporarily disrupt the WebSocket connection
2. Observe reconnection attempts
3. Verify successful reconnection

**Expected Results**:
- System should attempt to reconnect automatically
- Logs should show reconnection attempts
- After connection is restored, WebSocket should function normally

## Troubleshooting

If kill notifications are not working properly, check the following:

1. **Configuration Issues**:
   - Verify that `ENABLE_KILL_NOTIFICATIONS=true` is set
   - Verify that `PROCESS_ALL_KILLS=true` is set for testing
   - Check that Discord webhook/token is correct

2. **License Issues**:
   - Check license status in the application logs
   - Verify that the first-message enhancement works regardless of license

3. **Data Enrichment Issues**:
   - Check logs for ESI API errors or timeout issues
   - Verify that fallbacks are being used when data is missing

4. **WebSocket Issues**:
   - Check WebSocket connection status in logs
   - Look for any error messages related to WebSocket connection
   - Verify that the circuit breaker is not engaged

## Test Results Recording

When conducting these tests, record the following information:

1. Test date and time
2. Environment configuration used
3. Results of each test step
4. Any unexpected behavior
5. Relevant log snippets

This information will be valuable for diagnosing any issues and confirming that the refactoring changes are working as expected.