defmodule WandererNotifier.Schedulers.KillmailChartSchedulerTest do
  use ExUnit.Case, async: true
  import Mox

  alias WandererNotifier.Schedulers.KillmailChartScheduler

  setup :verify_on_exit!

  describe "execute/1" do
    test "executes on Sunday and sends chart to Discord" do
      # Set up mocks
      expect(WandererNotifier.MockConfig, :kill_charts_enabled?, fn -> true end)

      expect(WandererNotifier.MockConfig, :discord_channel_id_for, fn :kill_charts ->
        "success"
      end)

      # Create a Sunday date
      sunday = ~D[2024-03-24]

      result = KillmailChartScheduler.execute(sunday)
      assert {:ok, {:ok, %{status_code: 200}}, %{}} = result
    end

    test "skips execution on non-Sunday" do
      # Set up mocks
      expect(WandererNotifier.MockConfig, :kill_charts_enabled?, fn -> true end)

      # Create a Monday date
      monday = ~D[2024-03-25]

      result = KillmailChartScheduler.execute(monday)
      assert {:ok, :skipped, %{}} = result
    end

    test "handles errors when sending chart" do
      # Set up mocks
      expect(WandererNotifier.MockConfig, :kill_charts_enabled?, fn -> true end)
      expect(WandererNotifier.MockConfig, :discord_channel_id_for, fn :kill_charts -> "error" end)

      # Create a Sunday date
      sunday = ~D[2024-03-24]

      result = KillmailChartScheduler.execute(sunday)
      assert {:error, "Test error", %{}} = result
    end

    test "handles exceptions when sending chart" do
      # Set up mocks
      expect(WandererNotifier.MockConfig, :kill_charts_enabled?, fn -> true end)

      expect(WandererNotifier.MockConfig, :discord_channel_id_for, fn :kill_charts ->
        "exception"
      end)

      # Create a Sunday date
      sunday = ~D[2024-03-24]

      result = KillmailChartScheduler.execute(sunday)
      assert {:error, "Test exception", %{}} = result
    end

    test "handles unknown channel error" do
      # Set up mocks
      expect(WandererNotifier.MockConfig, :kill_charts_enabled?, fn -> true end)

      expect(WandererNotifier.MockConfig, :discord_channel_id_for, fn :kill_charts ->
        "unknown_channel"
      end)

      # Create a Sunday date
      sunday = ~D[2024-03-24]

      result = KillmailChartScheduler.execute(sunday)
      assert {:error, "Unknown Channel", %{}} = result
    end
  end

  describe "kill_charts_enabled?/0" do
    test "returns true when kill charts is enabled" do
      expect(WandererNotifier.MockConfig, :kill_charts_enabled?, fn -> true end)
      assert KillmailChartScheduler.kill_charts_enabled?() == true
    end

    test "returns false when kill charts is disabled" do
      expect(WandererNotifier.MockConfig, :kill_charts_enabled?, fn -> false end)
      assert KillmailChartScheduler.kill_charts_enabled?() == false
    end
  end

  describe "get_config/0" do
    test "returns correct configuration" do
      config = KillmailChartScheduler.get_config()

      assert config == %{
               type: :time,
               hour: 18,
               minute: 0,
               description: "Weekly character kill charts"
             }
    end
  end
end
