defmodule WandererNotifier.Logger.CategoryLoggerTest do
  use ExUnit.Case, async: true
  import ExUnit.CaptureLog
  alias WandererNotifier.Logger.CategoryLogger

  describe "processor category" do
    test "processor_debug/2" do
      log =
        capture_log(fn ->
          CategoryLogger.processor_debug("Debug message", key: "value")
        end)

      assert log =~ "[processor] Debug message"
      assert log =~ "key=value"
    end

    test "processor_info/2" do
      log =
        capture_log(fn ->
          CategoryLogger.processor_info("Info message")
        end)

      assert log =~ "[processor] Info message"
    end

    test "processor_warn/2" do
      log =
        capture_log([level: :warning], fn ->
          CategoryLogger.processor_warn("Warn message", count: 42)
        end)

      assert log =~ "[processor] Warn message"
      assert log =~ "count=42"
    end

    test "processor_error/2" do
      log =
        capture_log([level: :error], fn ->
          CategoryLogger.processor_error("Error message")
        end)

      assert log =~ "[processor] Error message"
    end

    test "processor_kv/2" do
      log =
        capture_log(fn ->
          CategoryLogger.processor_kv("Config value", true)
        end)

      assert log =~ "[processor] Config value"
      assert log =~ "value=true"
    end
  end

  describe "api category" do
    test "api_debug/2" do
      log =
        capture_log(fn ->
          CategoryLogger.api_debug("API debug", endpoint: "/test")
        end)

      assert log =~ "[api] API debug"
      assert log =~ "endpoint=\"/test\""
    end

    test "api_info/2" do
      log =
        capture_log(fn ->
          CategoryLogger.api_info("API info")
        end)

      assert log =~ "[api] API info"
    end

    test "api_warn/2" do
      log =
        capture_log([level: :warning], fn ->
          CategoryLogger.api_warn("API warning")
        end)

      assert log =~ "[api] API warning"
    end

    test "api_error/2" do
      log =
        capture_log([level: :error], fn ->
          CategoryLogger.api_error("API error", status: 500)
        end)

      assert log =~ "[api] API error"
      assert log =~ "status=500"
    end

    test "api_kv/2" do
      log =
        capture_log(fn ->
          CategoryLogger.api_kv("Request count", 100)
        end)

      assert log =~ "[api] Request count"
      assert log =~ "value=100"
    end
  end

  describe "cache category" do
    test "cache_debug/2" do
      log =
        capture_log(fn ->
          CategoryLogger.cache_debug("Cache debug")
        end)

      assert log =~ "[cache] Cache debug"
    end

    test "cache_info/2" do
      log =
        capture_log(fn ->
          CategoryLogger.cache_info("Cache info", hit_rate: 0.95)
        end)

      assert log =~ "[cache] Cache info"
      assert log =~ "hit_rate=0.95"
    end

    test "cache_warn/2" do
      log =
        capture_log([level: :warning], fn ->
          CategoryLogger.cache_warn("Cache warning")
        end)

      assert log =~ "[cache] Cache warning"
    end

    test "cache_error/2" do
      log =
        capture_log([level: :error], fn ->
          CategoryLogger.cache_error("Cache error")
        end)

      assert log =~ "[cache] Cache error"
    end

    test "cache_kv/2" do
      log =
        capture_log(fn ->
          CategoryLogger.cache_kv("Cache size", 1024)
        end)

      assert log =~ "[cache] Cache size"
      assert log =~ "value=1024"
    end
  end

  describe "notification category" do
    test "notification_debug/2" do
      log =
        capture_log(fn ->
          CategoryLogger.notification_debug("Notification debug")
        end)

      assert log =~ "[notification] Notification debug"
    end

    test "notification_info/2" do
      log =
        capture_log(fn ->
          CategoryLogger.notification_info("Notification sent", channel: "alerts")
        end)

      assert log =~ "[notification] Notification sent"
      assert log =~ "channel=\"alerts\""
    end

    test "notification_warn/2" do
      log =
        capture_log([level: :warning], fn ->
          CategoryLogger.notification_warn("Notification warning")
        end)

      assert log =~ "[notification] Notification warning"
    end

    test "notification_error/2" do
      log =
        capture_log([level: :error], fn ->
          CategoryLogger.notification_error("Notification failed")
        end)

      assert log =~ "[notification] Notification failed"
    end

    test "notification_kv/2" do
      log =
        capture_log(fn ->
          CategoryLogger.notification_kv("Queue size", 50)
        end)

      assert log =~ "[notification] Queue size"
      assert log =~ "value=50"
    end
  end

  describe "kill category" do
    test "kill_debug/2" do
      log =
        capture_log(fn ->
          CategoryLogger.kill_debug("Kill debug", killmail_id: 123)
        end)

      assert log =~ "[kill] Kill debug"
      assert log =~ "killmail_id=123"
    end

    test "kill_info/2" do
      log =
        capture_log(fn ->
          CategoryLogger.kill_info("Kill processed")
        end)

      assert log =~ "[kill] Kill processed"
    end

    test "kill_warn/2" do
      log =
        capture_log([level: :warning], fn ->
          CategoryLogger.kill_warn("Kill warning")
        end)

      assert log =~ "[kill] Kill warning"
    end

    test "kill_warning/2 delegates to kill_warn/2" do
      log =
        capture_log([level: :warning], fn ->
          CategoryLogger.kill_warning("Kill warning legacy")
        end)

      assert log =~ "[kill] Kill warning legacy"
    end

    test "kill_error/2" do
      log =
        capture_log([level: :error], fn ->
          CategoryLogger.kill_error("Kill error")
        end)

      assert log =~ "[kill] Kill error"
    end

    test "kill_kv/2" do
      log =
        capture_log(fn ->
          CategoryLogger.kill_kv("Kills processed", 42)
        end)

      assert log =~ "[kill] Kills processed"
      assert log =~ "value=42"
    end
  end

  describe "metadata handling" do
    test "handles map metadata" do
      log =
        capture_log(fn ->
          CategoryLogger.api_info("Test message", %{user_id: 123, action: "test"})
        end)

      assert log =~ "[api] Test message"
      assert log =~ "user_id=123"
      assert log =~ "action=\"test\""
    end

    test "handles keyword list metadata" do
      log =
        capture_log(fn ->
          CategoryLogger.system_info("Test message", system_id: 456, status: :active)
        end)

      assert log =~ "[system] Test message"
      assert log =~ "system_id=456"
      assert log =~ "status=:active"
    end

    test "handles empty metadata" do
      log =
        capture_log(fn ->
          CategoryLogger.config_info("Test message", [])
        end)

      assert log =~ "[config] Test message"
    end
  end
end
