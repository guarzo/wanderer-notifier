# Scheduler Framework

This directory contains a generic scheduler framework that standardizes how scheduled tasks are managed throughout the application.

## Overview

The scheduler framework provides a consistent approach to running periodic tasks, whether they need to be executed:
- At specific times of day (time-based scheduling)
- At regular intervals (interval-based scheduling)

The framework handles common concerns like:
- Feature flag awareness (enabled/disabled)
- Error handling
- Logging
- Configuration management
- Supervisor integration

## Components

### Core Components

- `WandererNotifier.Schedulers.Behaviour`: Defines the common interface for all schedulers
- `WandererNotifier.Schedulers.BaseScheduler`: Provides shared functionality for all scheduler types
- `WandererNotifier.Schedulers.IntervalScheduler`: Implements interval-based scheduling
- `WandererNotifier.Schedulers.TimeScheduler`: Implements time-based scheduling
- `WandererNotifier.Schedulers.Factory`: Factory module for creating schedulers with different configurations
- `WandererNotifier.Schedulers.Registry`: Tracks all registered schedulers
- `WandererNotifier.Schedulers.Supervisor`: Supervises all scheduler processes

### Specific Scheduler Implementations

- `WandererNotifier.Schedulers.TPSChartScheduler`: Time-based scheduler for TPS charts
- `WandererNotifier.Schedulers.ActivityChartScheduler`: Interval-based scheduler for activity charts
- `WandererNotifier.Schedulers.CharacterUpdateScheduler`: Interval-based scheduler for character updates
- `WandererNotifier.Schedulers.SystemUpdateScheduler`: Interval-based scheduler for system updates

## How to Create a New Scheduler

### Creating an Interval-Based Scheduler

```elixir
defmodule WandererNotifier.Schedulers.MyIntervalScheduler do
  @moduledoc """
  Documentation for the scheduler
  """
  
  require WandererNotifier.Schedulers.Factory
  require Logger
  
  # Create an interval-based scheduler
  WandererNotifier.Schedulers.Factory.create_scheduler(
    type: :interval,
    default_interval: 60 * 60 * 1000, # 1 hour in milliseconds
    enabled_check: &WandererNotifier.Config.some_feature_enabled?/0
  )
  
  @impl true
  def execute(state) do
    # Perform the scheduled task here
    result = do_something()
    
    case result do
      {:ok, data} -> {:ok, data, state}
      {:error, reason} -> {:error, reason, state}
    end
  end
end
```

### Creating a Time-Based Scheduler

```elixir
defmodule WandererNotifier.Schedulers.MyTimeScheduler do
  @moduledoc """
  Documentation for the scheduler
  """
  
  require WandererNotifier.Schedulers.Factory
  require Logger
  
  # Create a time-based scheduler
  WandererNotifier.Schedulers.Factory.create_scheduler(
    type: :time,
    default_hour: 12,
    default_minute: 0,
    hour_env_var: :my_scheduler_hour, # Optional env var for configuration
    minute_env_var: :my_scheduler_minute, # Optional env var for configuration
    enabled_check: &WandererNotifier.Config.some_feature_enabled?/0
  )
  
  @impl true
  def execute(state) do
    # Perform the scheduled task here
    result = do_something()
    
    case result do
      {:ok, data} -> {:ok, data, state}
      {:error, reason} -> {:error, reason, state}
    end
  end
end
```

### Adding the Scheduler to the Supervisor

Update the `WandererNotifier.Schedulers.Supervisor` module to include the new scheduler:

```elixir
# Inside init/1
schedulers = [
  {WandererNotifier.Schedulers.TPSChartScheduler, []},
  {WandererNotifier.Schedulers.ActivityChartScheduler, []},
  {WandererNotifier.Schedulers.CharacterUpdateScheduler, []},
  {WandererNotifier.Schedulers.SystemUpdateScheduler, []},
  {WandererNotifier.Schedulers.MyNewScheduler, []} # Add your new scheduler here
]
```

## Registry Usage

The scheduler registry tracks all registered schedulers and provides utilities to manage them:

```elixir
# Get information about all schedulers
schedulers = WandererNotifier.Schedulers.Registry.get_all_schedulers()

# Trigger execution of all schedulers
WandererNotifier.Schedulers.Registry.execute_all()
```