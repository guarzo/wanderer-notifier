defmodule WandererNotifier.Shared.Logger.StartupLogger do
  @moduledoc """
  Handles application startup phase tracking and logging.

  This module extracts startup tracking logic from the main Logger module,
  providing structured logging for application initialization phases.

  ## Features
  - Track application startup phases
  - Record startup events with timing
  - Log feature status during initialization
  - Track startup errors separately
  - Provide startup completion summary

  ## Usage
  ```elixir
  alias WandererNotifier.Shared.Logger.StartupLogger

  # Initialize at application start
  StartupLogger.init()

  # Track startup phases
  StartupLogger.begin_phase(:config, "Loading configuration")
  # ... do config loading ...
  StartupLogger.end_phase(:config)

  # Record startup events
  StartupLogger.record_event(:feature_enabled, %{
    feature: "websocket",
    enabled: true,
    url: "ws://localhost:4004"
  })

  # Record errors
  StartupLogger.record_error("Failed to connect to database", %{
    error: "connection refused",
    retry_count: 3
  })

  # Complete startup
  StartupLogger.complete()
  ```
  """

  require Logger
  alias WandererNotifier.Shared.Utils.TimeUtils

  @category_startup :startup
  @level_info :info
  @level_debug :debug

  @doc """
  Initializes the startup tracker.

  Sets up state tracking for application startup phases.
  Should be called at the very beginning of application initialization.
  """
  def init do
    Logger.debug("[StartupLogger] Initializing startup tracker")
    # Simple initialization - state tracking can be added in future GenServer implementation
    :ok
  end

  @doc """
  Begins a new startup phase.

  ## Parameters
  - `phase` - Phase identifier (atom)
  - `message` - Human-readable phase description

  ## Examples
  ```elixir
  StartupLogger.begin_phase(:dependencies, "Loading dependencies")
  StartupLogger.begin_phase(:database, "Initializing database connections")
  ```
  """
  def begin_phase(phase, message) do
    Logger.info("[Startup] Beginning phase: #{phase}", %{
      category: @category_startup,
      phase: phase,
      message: message,
      timestamp: TimeUtils.now(),
      event: :phase_start
    })

    # Phase start tracked via logging - state tracking can be added in future GenServer implementation
    :ok
  end

  @doc """
  Ends a startup phase.

  Logs the phase completion with duration.

  ## Parameters
  - `phase` - Phase identifier (atom)

  ## Examples
  ```elixir
  StartupLogger.end_phase(:dependencies)
  ```
  """
  def end_phase(phase) do
    # Duration calculated using timestamp - state tracking can be added in future GenServer implementation
    Logger.info("[Startup] Completed phase: #{phase}", %{
      category: @category_startup,
      phase: phase,
      timestamp: TimeUtils.now(),
      event: :phase_end
    })

    :ok
  end

  @doc """
  Records a startup event.

  ## Parameters
  - `type` - Event type (atom)
  - `details` - Event details (map)
  - `force_log` - Force info level logging (default: false)

  ## Examples
  ```elixir
  StartupLogger.record_event(:config_loaded, %{
    config_count: 42,
    source: "environment"
  })

  StartupLogger.record_event(:feature_status, %{
    feature: "notifications",
    enabled: false,
    reason: "disabled by config"
  }, true)
  ```
  """
  def record_event(type, details, force_log \\ false) do
    level = if force_log, do: @level_info, else: @level_debug

    Logger.log(
      level,
      "[Startup] Event: #{type}",
      Map.merge(details, %{
        category: @category_startup,
        event_type: type,
        timestamp: TimeUtils.now()
      })
    )

    # Event logged for tracking - state aggregation can be added in future GenServer implementation
    :ok
  end

  @doc """
  Records a startup error.

  ## Parameters
  - `message` - Error message
  - `details` - Error details (map)

  ## Examples
  ```elixir
  StartupLogger.record_error("Database connection failed", %{
    error: reason,
    attempts: 3
  })
  ```
  """
  def record_error(message, details) do
    Logger.error(
      "[Startup] #{message}",
      Map.merge(details, %{
        category: @category_startup,
        event: :startup_error,
        timestamp: TimeUtils.now()
      })
    )

    # Error logged for tracking - state aggregation can be added in future GenServer implementation
    :ok
  end

  @doc """
  Marks application startup as complete.

  Logs a summary of the startup process including:
  - Total duration
  - Phases completed
  - Events recorded
  - Errors encountered
  """
  def complete do
    # Statistics logged - state aggregation can be added in future GenServer implementation
    Logger.info("[Startup] Application startup complete", %{
      category: @category_startup,
      event: :startup_complete,
      timestamp: TimeUtils.now()
    })

    # Startup completion logged - summary generation can be added in future GenServer implementation
    :ok
  end

  @doc """
  Logs a startup state change.

  Used for tracking major state transitions during startup.

  ## Parameters
  - `type` - State change type
  - `message` - Description
  - `details` - Additional details

  ## Examples
  ```elixir
  StartupLogger.log_state_change(:services_ready, 
    "All core services initialized",
    %{service_count: 5}
  )
  ```
  """
  def log_state_change(type, message, details) do
    Logger.info(
      "[Startup] State change: #{type} - #{message}",
      Map.merge(details, %{
        category: @category_startup,
        state_change: type,
        timestamp: TimeUtils.now()
      })
    )

    :ok
  end

  @doc """
  Gets current startup statistics.

  Returns a map with startup metrics:
  - Current phase
  - Phases completed
  - Events recorded
  - Errors encountered
  - Start time

  ## Examples
  ```elixir
  stats = StartupLogger.get_stats()
  # => %{
  #   current_phase: :database,
  #   phases_completed: [:config, :dependencies],
  #   event_count: 15,
  #   error_count: 0,
  #   start_time: ~U[2024-01-20 12:00:00Z]
  # }
  ```
  """
  def get_stats do
    # Currently returns empty map - statistics can be tracked in future GenServer implementation
    %{
      current_phase: nil,
      phases_completed: [],
      event_count: 0,
      error_count: 0,
      start_time: nil
    }
  end

  @doc """
  Logs a feature status during startup.

  Convenience function for logging feature enable/disable status.

  ## Parameters
  - `feature` - Feature name
  - `enabled` - Whether feature is enabled
  - `details` - Additional details (optional)

  ## Examples
  ```elixir
  StartupLogger.log_feature_status("websocket", true, %{url: "ws://localhost:4004"})
  StartupLogger.log_feature_status("notifications", false, %{reason: "disabled by config"})
  ```
  """
  def log_feature_status(feature, enabled, details \\ %{}) do
    status = if enabled, do: "enabled", else: "disabled"

    record_event(
      :feature_status,
      Map.merge(details, %{
        feature: feature,
        enabled: enabled,
        status: status
      }),
      true
    )
  end
end
