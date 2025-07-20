defmodule WandererNotifier.Shared.Logger.BatchLoggerTest do
  use ExUnit.Case, async: true
  import ExUnit.CaptureLog
  alias WandererNotifier.Shared.Logger.BatchLogger

  describe "initialization" do
    test "init/0 initializes with default interval" do
      log =
        capture_log([level: :debug], fn ->
          assert :ok = BatchLogger.init()
        end)

      assert log =~ "[BatchLogger] Initializing with interval: 5000ms"
    end

    test "init/1 accepts custom interval" do
      log =
        capture_log([level: :debug], fn ->
          assert :ok = BatchLogger.init(interval: 10_000)
        end)

      assert log =~ "[BatchLogger] Initializing with interval: 10000ms"
    end
  end

  describe "event counting" do
    test "count_event/3 with immediate logging" do
      log =
        capture_log(fn ->
          BatchLogger.count_event(:test_event, %{data: "value"}, true)
        end)

      assert log =~ "[batch] Event: test_event"
      assert log =~ "batch=true"
      assert log =~ "immediate=true"
      assert log =~ "data=value"
    end

    test "count_event/2 without immediate logging" do
      # This should not produce any log output in current implementation
      log =
        capture_log(fn ->
          assert :ok = BatchLogger.count_event(:test_event, %{data: "value"})
        end)

      # Current implementation doesn't log non-immediate events
      assert log == ""
    end

    test "count_event/3 with false immediate flag" do
      log =
        capture_log(fn ->
          assert :ok = BatchLogger.count_event(:test_event, %{data: "value"}, false)
        end)

      # Should not log when immediate is false
      assert log == ""
    end
  end

  describe "flushing" do
    test "flush_all/0" do
      log =
        capture_log([level: :debug], fn ->
          assert :ok = BatchLogger.flush_all()
        end)

      assert log =~ "[BatchLogger] Flushing all batch logs"
    end

    test "flush_category/1" do
      log =
        capture_log([level: :debug], fn ->
          assert :ok = BatchLogger.flush_category(:test_category)
        end)

      assert log =~ "[BatchLogger] Flushing batch logs for category: test_category"
    end

    test "handle_flush/0 with default interval" do
      log =
        capture_log([level: :debug], fn ->
          assert :ok = BatchLogger.handle_flush()
        end)

      assert log =~ "[BatchLogger] Flushing all batch logs"
    end

    test "handle_flush/1 with custom interval" do
      log =
        capture_log([level: :debug], fn ->
          assert :ok = BatchLogger.handle_flush(10_000)
        end)

      assert log =~ "[BatchLogger] Flushing all batch logs"
    end
  end

  describe "statistics and management" do
    test "get_stats/0 returns empty map" do
      # Current implementation returns empty map
      assert BatchLogger.get_stats() == %{}
    end

    test "reset/0" do
      log =
        capture_log([level: :debug], fn ->
          assert :ok = BatchLogger.reset()
        end)

      assert log =~ "[BatchLogger] Resetting all batch counters"
    end

    test "configure/1" do
      log =
        capture_log(fn ->
          assert :ok = BatchLogger.configure(enabled: false, interval: 15_000)
        end)

      assert log =~ "[BatchLogger] Configuration updated"
      assert log =~ "interval=15000"
    end
  end

  describe "edge cases" do
    test "count_event with empty details" do
      log =
        capture_log(fn ->
          BatchLogger.count_event(:empty_event, %{}, true)
        end)

      assert log =~ "[batch] Event: empty_event"
      assert log =~ "batch=true"
      assert log =~ "immediate=true"
    end

    test "count_event with complex details" do
      complex_details = %{
        list: [1, 2, 3],
        map: %{nested: "value"},
        string: "test string",
        number: 42
      }

      log =
        capture_log(fn ->
          BatchLogger.count_event(:complex_event, complex_details, true)
        end)

      assert log =~ "[batch] Event: complex_event"
      assert log =~ "batch=true"
      assert log =~ "immediate=true"
    end

    test "flush_category with atom category" do
      log =
        capture_log(fn ->
          BatchLogger.flush_category(:api_requests)
        end)

      assert log =~ "category: api_requests"
    end

    test "flush_category with string category" do
      log =
        capture_log(fn ->
          BatchLogger.flush_category("string_category")
        end)

      assert log =~ "category: string_category"
    end
  end

  describe "configuration options" do
    test "configure with enabled flag" do
      log =
        capture_log(fn ->
          BatchLogger.configure(enabled: true)
        end)

      assert log =~ "enabled=true"
    end

    test "configure with max_batch_size" do
      log =
        capture_log(fn ->
          BatchLogger.configure(max_batch_size: 500)
        end)

      assert log =~ "max_batch_size=500"
    end

    test "configure with multiple options" do
      log =
        capture_log(fn ->
          BatchLogger.configure(
            enabled: true,
            interval: 7_000,
            max_batch_size: 250
          )
        end)

      assert log =~ "enabled=true"
      assert log =~ "interval=7000"
      assert log =~ "max_batch_size=250"
    end
  end
end
