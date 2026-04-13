defmodule WandererNotifier.Domains.Notifications.Discord.ConnectionHealthTest do
  use ExUnit.Case, async: false

  alias WandererNotifier.Domains.Notifications.Discord.ConnectionHealth

  setup do
    # Stop existing instance if running, start fresh for each test
    case GenServer.whereis(ConnectionHealth) do
      nil -> :ok
      pid -> GenServer.stop(pid, :normal)
    end

    {:ok, _pid} = ConnectionHealth.start_link([])

    on_exit(fn ->
      case GenServer.whereis(ConnectionHealth) do
        nil -> :ok
        pid -> GenServer.stop(pid, :normal)
      end
    end)

    :ok
  end

  describe "record_success/0" do
    test "increments total_successes counter" do
      ConnectionHealth.record_success()
      ConnectionHealth.record_success()
      # Give GenServer time to process casts
      Process.sleep(50)

      {:ok, status} = ConnectionHealth.get_health_status()
      assert status.total_successes == 2
    end
  end

  describe "record_failure/2" do
    test "increments total_failures counter and adds to failed_kills" do
      ConnectionHealth.record_failure(:timeout, "kill-123")
      Process.sleep(50)

      {:ok, status} = ConnectionHealth.get_health_status()
      assert status.total_failures == 1
      assert length(status.failed_kills) == 1
      assert hd(status.failed_kills).killmail_id == "kill-123"
    end
  end

  describe "record_failed_killmail/2" do
    test "adds to failed_kills list without incrementing counters" do
      ConnectionHealth.record_failed_killmail("kill-456", :partial_failure)
      Process.sleep(50)

      {:ok, status} = ConnectionHealth.get_health_status()
      assert status.total_failures == 0
      assert status.total_successes == 0
      assert length(status.failed_kills) == 1
      assert hd(status.failed_kills).killmail_id == "kill-456"
    end
  end
end
