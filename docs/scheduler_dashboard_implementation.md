# Scheduler Dashboard Implementation

## Overview

We've implemented a comprehensive scheduler dashboard that allows monitoring and controlling all schedulers in the system. The dashboard shows scheduler status, execution history, and provides controls to manually trigger scheduler execution.

## API Endpoints

The following API endpoints have been added to support the scheduler dashboard:

### 1. `/api/debug/scheduler-stats` (GET)

Returns detailed statistics about all schedulers with formatted data for the dashboard:

```json
{
  "schedulers": [
    {
      "id": "WandererNotifier.Schedulers.SystemUpdateScheduler",
      "name": "System Update",
      "module": "WandererNotifier.Schedulers.SystemUpdateScheduler",
      "type": "interval",
      "enabled": true,
      "interval": 300000,
      "last_run": {
        "timestamp": "2023-06-01T10:30:00Z",
        "relative": "2 hours ago"
      },
      "next_run": {
        "timestamp": "2023-06-01T15:30:00Z",
        "relative": "In 3 hours"
      },
      "stats": {
        "success_count": 42,
        "error_count": 2,
        "last_duration_ms": 1500,
        "last_result": { "ok": "success" },
        "last_error": null,
        "retry_count": 0
      },
      "config": {
        "interval_ms": 300000,
        "enabled": true
      }
    }
  ],
  "summary": {
    "total": 5,
    "enabled": 4,
    "disabled": 1,
    "by_type": {
      "interval": 3,
      "time": 2
    }
  }
}
```

### 2. `/api/debug/schedulers` (GET)

Returns raw scheduler data from the registry:

```json
[
  {
    "module": "WandererNotifier.Schedulers.SystemUpdateScheduler",
    "enabled": true,
    "config": {
      "interval_ms": 300000,
      "enabled": true
    }
  }
]
```

### 3. `/api/debug/schedulers/execute` (POST)

Executes all enabled schedulers in the system. Returns:

```json
{
  "success": true,
  "message": "All schedulers executed"
}
```

### 4. `/api/debug/scheduler/:id/execute` (POST)

Executes a specific scheduler identified by its ID. Returns:

```json
{
  "success": true,
  "message": "Scheduler executed"
}
```

## Implementation Details

The implementation uses the enhanced `BaseScheduler` which now includes:

1. **Health Monitoring**: Each scheduler exposes a `health_check/0` function that returns detailed state information.

2. **Scheduler Registry**: All schedulers register themselves with the `SchedulerRegistry` which keeps track of available schedulers.

3. **Automatic Registration**: Schedulers automatically register with the registry during initialization, with retry logic to handle timing issues.

4. **Execution History**: Schedulers track their execution history, including success/failure status, errors, and timestamps.

5. **Standardized Error Handling**: All schedulers use a consistent error handling pattern with automatic retries.

## Frontend Integration

The frontend dashboard in `src/components/SchedulerDashboard.jsx` connects to these endpoints to:

1. Display a summary view of all schedulers and their status
2. Show detailed information for each scheduler in a card view
3. Enable filtering by scheduler type and status
4. Allow manual execution of individual schedulers or all schedulers
5. Provide relative timestamps for last and next execution times

## Testing

To validate the dashboard functionality:

1. Start the application
2. Access the scheduler dashboard at `/schedulers`
3. Verify all schedulers appear correctly
4. Check that the summary statistics match the actual scheduler counts
5. Test the filter functionality
6. Try executing schedulers manually and verify they run

## Future Improvements

1. Add success/error counters to each scheduler to track performance metrics
2. Implement duration tracking for execution time stats
3. Add the ability to temporarily disable/enable schedulers via the dashboard
4. Provide more detailed execution history
