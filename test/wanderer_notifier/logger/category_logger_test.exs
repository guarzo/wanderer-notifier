defmodule WandererNotifier.Shared.Logger.CategoryLoggerTest do
  use ExUnit.Case, async: true
  import ExUnit.CaptureLog
  alias WandererNotifier.Shared.Logger.Logger

  describe "simplified logger categories" do
    test "processor_debug/2" do
      log =
        capture_log(fn ->
          Logger.processor_debug("Debug message", key: "value")
        end)

      assert log =~ "Debug message"
      assert log =~ "category: :processor"
    end

    test "processor_info/2" do
      log =
        capture_log(fn ->
          Logger.processor_info("Info message")
        end)

      assert log =~ "Info message"
      assert log =~ "category: :processor"
    end

    test "api_info/2" do
      log =
        capture_log(fn ->
          Logger.api_info("API message", service: "test")
        end)

      assert log =~ "API message"
      assert log =~ "category: :api"
    end

    test "api_debug/2" do
      log =
        capture_log(fn ->
          Logger.api_debug("API debug", endpoint: "/test")
        end)

      assert log =~ "API debug"
      assert log =~ "category: :api"
    end

    test "api_error/2" do
      log =
        capture_log([level: :error], fn ->
          Logger.api_error("API error", status: 500)
        end)

      assert log =~ "API error"
      assert log =~ "category: :api"
    end

    test "kill_info/2" do
      log =
        capture_log(fn ->
          Logger.kill_info("Kill message", killmail_id: 123)
        end)

      assert log =~ "Kill message"
      assert log =~ "category: :kill"
    end

    test "kill_debug/2" do
      log =
        capture_log(fn ->
          Logger.kill_debug("Kill debug", killmail_id: 123)
        end)

      assert log =~ "Kill debug"
      assert log =~ "category: :kill"
    end

    test "system_info/2" do
      log =
        capture_log(fn ->
          Logger.system_info("System message", system_id: 456)
        end)

      assert log =~ "System message"
      assert log =~ "category: :system"
    end

    test "startup_info/2" do
      log =
        capture_log(fn ->
          Logger.startup_info("Startup message", component: "test")
        end)

      assert log =~ "Startup message"
      assert log =~ "category: :startup"
    end

    test "cache_info/2" do
      log =
        capture_log(fn ->
          Logger.cache_info("Cache message", hit_rate: 0.95)
        end)

      assert log =~ "Cache message"
      assert log =~ "category: :cache"
    end
  end

  describe "basic logging functions" do
    test "debug/2" do
      log =
        capture_log(fn ->
          Logger.debug("Debug message", component: "test")
        end)

      assert log =~ "Debug message"
    end

    test "info/2" do
      log =
        capture_log(fn ->
          Logger.info("Info message", component: "test")
        end)

      assert log =~ "Info message"
    end

    test "warn/2" do
      log =
        capture_log([level: :warning], fn ->
          Logger.warn("Warning message", component: "test")
        end)

      assert log =~ "Warning message"
    end

    test "error/2" do
      log =
        capture_log([level: :error], fn ->
          Logger.error("Error message", component: "test")
        end)

      assert log =~ "Error message"
    end
  end

  describe "metadata handling" do
    test "handles keyword list metadata" do
      log =
        capture_log(fn ->
          Logger.api_info("Test message", user_id: 123, action: "test")
        end)

      assert log =~ "Test message"
      assert log =~ "category: :api"
    end

    test "handles empty metadata" do
      log =
        capture_log(fn ->
          Logger.info("Test message", [])
        end)

      assert log =~ "Test message"
    end
  end
end
