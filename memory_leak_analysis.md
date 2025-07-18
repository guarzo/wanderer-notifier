# Memory Leak Analysis Report

## Critical Issue Found

### 1. **PerformanceMonitor - Unbounded Alert List Growth** ⚠️ CRITICAL

**Location**: `/workspace/lib/wanderer_notifier/metrics/performance_monitor.ex`

**Line 284**:
```elixir
recent_alerts: new_alerts ++ state.recent_alerts
```

**Problem**: The `recent_alerts` list grows unboundedly. New alerts are continuously prepended to the list, but old alerts are never removed. This will cause memory usage to grow over time as alerts accumulate.

**Impact**: High - This is likely a major contributor to the 12GB memory usage. If the system generates alerts frequently (e.g., during periods of high load or degraded performance), this list will grow rapidly.

**Fix Required**:
```elixir
# Limit the recent_alerts to a reasonable number (e.g., 100 most recent)
recent_alerts: Enum.take(new_alerts ++ state.recent_alerts, 100)
```

## Minor Issues Found

### 2. Cache.PerformanceMonitor - Alert Map Cleanup

**Location**: `/workspace/lib/wanderer_notifier/cache/performance_monitor.ex`

**Issue**: The `alerts` map in state accumulates entries but doesn't clean up resolved alerts. While not as severe as unbounded list growth, this could contribute to memory usage over very long periods.

**Recommendation**: Implement periodic cleanup of resolved alerts older than a certain threshold.

## Properly Bounded Data Structures (Good)

The following modules properly limit their data accumulation:

1. **EventAnalytics** (`event_analytics.ex`):
   - `pattern_cache`: Limited to 100 events per pattern
   - `latency_samples`: Limited to 100 samples
   - `event_buckets`: Cleaned up periodically based on window size

2. **MessageTracker** (`message_tracker.ex`):
   - Uses ETS with proper TTL and size limits
   - Implements automatic cleanup of expired entries
   - Has maximum size constraints

3. **ConnectionMonitor** (`connection_monitor.ex`):
   - `ping_samples`: Limited to 10 samples per connection

4. **WebSocketClient** (`websocket_client.ex`):
   - State is replaced on updates, not accumulated
   - Uses MapSets for subscriptions which are replaced, not grown

## Additional Observations

### Adaptive Memory Baseline

The PerformanceMonitor implements adaptive smoothing for memory baselines to prevent "baseline creep" during memory spikes. This is a good practice but won't prevent the alert list issue.

### Memory Spike Detection

The system can detect memory spikes and categorize them by severity (2x, 3x, 5x baseline), but the unbounded alert list means these alerts accumulate forever.

## Recommendations

1. **Immediate Fix**: Apply the fix to limit `recent_alerts` in PerformanceMonitor
2. **Add Monitoring**: Log the size of `recent_alerts` periodically to verify the fix
3. **Review Alert Retention**: Consider implementing a time-based cleanup (e.g., remove alerts older than 24 hours)
4. **Add Memory Profiling**: Use `:observer.start()` or `:recon` to identify other memory consumers
5. **Implement Alert Archiving**: Instead of keeping all alerts in memory, consider archiving old alerts to disk or a database

## Testing the Fix

After applying the fix, monitor:
- Memory usage over time
- Size of the `recent_alerts` list
- Alert generation frequency
- System performance during high-alert periods