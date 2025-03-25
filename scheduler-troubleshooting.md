# Scheduler Registration Troubleshooting Tasks

## Problem Summary
The scheduler dashboard shows configured schedulers, but none are being properly registered with the `SchedulerRegistry`. This suggests a disconnect between the application's configuration and the runtime behavior of scheduler processes.

## Investigation Tasks

### 1. Inspect Registry Functionality
- [ ] Verify that `WandererNotifier.Schedulers.Registry` is properly started
  ```elixir
  # In an IEx console
  Process.whereis(WandererNotifier.Schedulers.Registry)
  ```
- [ ] Check registry state to confirm it's initialized correctly
  ```elixir
  :sys.get_state(WandererNotifier.Schedulers.Registry)
  ```
- [ ] Monitor registry registration calls during startup
  ```elixir
  :sys.trace(WandererNotifier.Schedulers.Registry, true)
  ```

### 2. Examine Scheduler Startup Process
- [ ] Check supervisor tree to verify schedulers are being started
  ```elixir
  # Find the scheduler supervisor
  Process.whereis(WandererNotifier.Schedulers.Supervisor)
  # Get its children
  Supervisor.which_children(WandererNotifier.Schedulers.Supervisor)
  ```
- [ ] Verify individual scheduler processes exist for each configured scheduler
  ```elixir
  # Examples for specific schedulers
  Process.whereis(WandererNotifier.Schedulers.ActivityChartScheduler)
  Process.whereis(WandererNotifier.Schedulers.SystemUpdateScheduler)
  ```
- [ ] Check for any crash reports in logs related to schedulers

### 3. Review Code Paths
- [ ] Add detailed logging in the `BaseScheduler.__using__` macro to track initialization
- [ ] Add debug logging in `SchedulerRegistry.register/1` to confirm it's being called
- [ ] Review feature flags that control which schedulers are loaded
  ```elixir
  WandererNotifier.Core.Config.kill_charts_enabled?()
  WandererNotifier.Core.Config.map_charts_enabled?()
  ```
- [ ] Verify database readiness check is passing if relevant for scheduler startup

### 4. Fix Implementation Issues
- [ ] Fix any issues with scheduler initialization in `BaseScheduler`
- [ ] Ensure `register` is being called for all schedulers after initialization
- [ ] Check for timing issues where the registry service might not be ready when schedulers try to register
- [ ] Fix any feature flag issues or clarify which schedulers should be active

## Potential Solutions

### Option 1: Fix Registration Process
- [ ] Add explicit logging of registration success/failure
- [ ] Add retry logic for registration if initial attempt fails
- [ ] Ensure registry service is fully initialized before schedulers attempt registration

### Option 2: Enhance Registry to Auto-discover Schedulers
- [ ] Modify the registry to actively query for running schedulers rather than requiring them to register
- [ ] Implement a periodic check that adds any running schedulers that aren't yet registered

### Option 3: Direct Configuration-Based Approach
- [ ] Remove dependency on registration process for the dashboard
- [ ] Always use configured schedulers as the source of truth
- [ ] Query process information to determine runtime state

## Implementation Plan
1. Add enhanced logging around scheduler startup and registration
2. Test startup sequence to identify precise point of failure
3. Fix specific issue based on findings
4. Add tests to ensure registration process works correctly
5. Update scheduler dashboard to handle edge cases

## Long-term Improvements
- [ ] Add health monitoring for all schedulers
- [ ] Implement self-healing for schedulers that fail to register
- [ ] Add metrics collection for scheduler performance
- [ ] Improve dashboard to show historical execution data