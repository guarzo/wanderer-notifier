defmodule WandererNotifier.Logger.StartupLoggerTest do
  use ExUnit.Case, async: true
  import ExUnit.CaptureLog
  alias WandererNotifier.Logger.StartupLogger

  describe "initialization" do
    test "init/0 initializes startup tracker" do
      log =
        capture_log(fn ->
          assert :ok = StartupLogger.init()
        end)

      assert log =~ "[StartupLogger] Initializing startup tracker"
    end
  end

  describe "phase tracking" do
    test "begin_phase/2" do
      log =
        capture_log(fn ->
          assert :ok = StartupLogger.begin_phase(:config, "Loading configuration")
        end)

      assert log =~ "[Startup] Beginning phase: config"
      assert log =~ "Loading configuration"
      assert log =~ "phase=:config"
      assert log =~ "event=:phase_start"
      assert log =~ "timestamp="
    end

    test "end_phase/1" do
      log =
        capture_log(fn ->
          assert :ok = StartupLogger.end_phase(:config)
        end)

      assert log =~ "[Startup] Completed phase: config"
      assert log =~ "phase=:config"
      assert log =~ "event=:phase_end"
      assert log =~ "timestamp="
    end

    test "begin_phase with atom phase" do
      log =
        capture_log(fn ->
          StartupLogger.begin_phase(:database, "Connecting to database")
        end)

      assert log =~ "Beginning phase: database"
      assert log =~ "Connecting to database"
    end

    test "end_phase with atom phase" do
      log =
        capture_log(fn ->
          StartupLogger.end_phase(:database)
        end)

      assert log =~ "Completed phase: database"
    end
  end

  describe "event recording" do
    test "record_event/2 with debug level" do
      log =
        capture_log(fn ->
          assert :ok = StartupLogger.record_event(:config_loaded, %{count: 42})
        end)

      assert log =~ "Event: config_loaded"
      assert log =~ "count=42"
      assert log =~ "event_type=:config_loaded"
      assert log =~ "timestamp="
    end

    test "record_event/3 with force_log true" do
      log =
        capture_log([level: :info], fn ->
          assert :ok = StartupLogger.record_event(:feature_enabled, %{feature: "websocket"}, true)
        end)

      assert log =~ "Event: feature_enabled"
      assert log =~ "feature=\"websocket\""
      assert log =~ "event_type=:feature_enabled"
    end

    test "record_event/3 with force_log false" do
      log =
        capture_log(fn ->
          StartupLogger.record_event(:minor_event, %{data: "test"}, false)
        end)

      # Should still log but at debug level
      assert log =~ "Event: minor_event"
    end

    test "record_event with complex data" do
      complex_data = %{
        list: [1, 2, 3],
        map: %{nested: "value"},
        string: "test",
        number: 42
      }

      log =
        capture_log(fn ->
          StartupLogger.record_event(:complex_event, complex_data, true)
        end)

      assert log =~ "Event: complex_event"
      assert log =~ "event_type=:complex_event"
    end
  end

  describe "error recording" do
    test "record_error/2" do
      log =
        capture_log([level: :error], fn ->
          assert :ok =
                   StartupLogger.record_error("Database connection failed", %{
                     error: "connection refused",
                     attempts: 3
                   })
        end)

      assert log =~ "[Startup] Database connection failed"
      assert log =~ "error=\"connection refused\""
      assert log =~ "attempts=3"
      assert log =~ "event=:startup_error"
      assert log =~ "timestamp="
    end

    test "record_error with simple message" do
      log =
        capture_log([level: :error], fn ->
          StartupLogger.record_error("Simple error", %{})
        end)

      assert log =~ "[Startup] Simple error"
      assert log =~ "event=:startup_error"
    end

    test "record_error with detailed information" do
      log =
        capture_log([level: :error], fn ->
          StartupLogger.record_error("Configuration error", %{
            file: "config.exs",
            line: 42,
            reason: "invalid syntax"
          })
        end)

      assert log =~ "Configuration error"
      assert log =~ "file=\"config.exs\""
      assert log =~ "line=42"
      assert log =~ "reason=\"invalid syntax\""
    end
  end

  describe "startup completion" do
    test "complete/0" do
      log =
        capture_log(fn ->
          assert :ok = StartupLogger.complete()
        end)

      assert log =~ "[Startup] Application startup complete"
      assert log =~ "event=:startup_complete"
      assert log =~ "timestamp="
    end
  end

  describe "state changes" do
    test "log_state_change/3" do
      log =
        capture_log(fn ->
          assert :ok =
                   StartupLogger.log_state_change(
                     :services_ready,
                     "All core services initialized",
                     %{service_count: 5}
                   )
        end)

      assert log =~ "[Startup] State change: services_ready - All core services initialized"
      assert log =~ "service_count=5"
      assert log =~ "state_change=:services_ready"
      assert log =~ "timestamp="
    end

    test "log_state_change with empty details" do
      log =
        capture_log(fn ->
          StartupLogger.log_state_change(:ready, "System ready", %{})
        end)

      assert log =~ "State change: ready - System ready"
      assert log =~ "state_change=:ready"
    end
  end

  describe "feature status logging" do
    test "log_feature_status/2 with enabled feature" do
      log =
        capture_log(fn ->
          assert :ok = StartupLogger.log_feature_status("websocket", true)
        end)

      assert log =~ "Event: feature_status"
      assert log =~ "feature=\"websocket\""
      assert log =~ "enabled=true"
      assert log =~ "status=\"enabled\""
    end

    test "log_feature_status/2 with disabled feature" do
      log =
        capture_log(fn ->
          StartupLogger.log_feature_status("notifications", false)
        end)

      assert log =~ "Event: feature_status"
      assert log =~ "feature=\"notifications\""
      assert log =~ "enabled=false"
      assert log =~ "status=\"disabled\""
    end

    test "log_feature_status/3 with additional details" do
      log =
        capture_log(fn ->
          assert :ok =
                   StartupLogger.log_feature_status("database", true, %{
                     host: "localhost",
                     port: 5432
                   })
        end)

      assert log =~ "feature=\"database\""
      assert log =~ "enabled=true"
      assert log =~ "host=\"localhost\""
      assert log =~ "port=5432"
    end
  end

  describe "statistics" do
    test "get_stats/0 returns default stats" do
      stats = StartupLogger.get_stats()

      assert is_map(stats)
      assert stats[:current_phase] == nil
      assert stats[:phases_completed] == []
      assert stats[:event_count] == 0
      assert stats[:error_count] == 0
      assert stats[:start_time] == nil
    end
  end

  describe "edge cases" do
    test "phase tracking with string phases" do
      log =
        capture_log(fn ->
          StartupLogger.begin_phase("string_phase", "String phase description")
        end)

      assert log =~ "Beginning phase: string_phase"
    end

    test "event recording with empty details" do
      log =
        capture_log(fn ->
          StartupLogger.record_event(:empty_event, %{})
        end)

      assert log =~ "Event: empty_event"
      assert log =~ "event_type=:empty_event"
    end

    test "error recording with nil details" do
      log =
        capture_log([level: :error], fn ->
          StartupLogger.record_error("Error message", nil)
        end)

      # Should handle nil gracefully
      assert log =~ "[Startup] Error message"
    end

    test "feature status with atom feature name" do
      log =
        capture_log(fn ->
          StartupLogger.log_feature_status(:cache, true)
        end)

      assert log =~ "feature=:cache"
      assert log =~ "enabled=true"
    end
  end
end
