defmodule WandererNotifier.Schedulers.KillmailChartSchedulerTest do
  use ExUnit.Case, async: false
  import Mock

  alias WandererNotifier.Schedulers.KillmailChartScheduler
  alias WandererNotifier.ChartService.KillmailChartAdapter
  alias WandererNotifier.Core.Config

  describe "execute/1" do
    test "executes on Sunday and sends chart to Discord" do
      # Mock Date.utc_today to return a Sunday (day 7)
      with_mocks([
        {Date, [], [utc_today: fn -> ~D[2023-01-01] end, day_of_week: fn _ -> 7 end]},
        {Config, [],
         [
           discord_channel_id_for: fn :kill_charts -> "123456789" end,
           kill_charts_enabled?: fn -> true end
         ]},
        {KillmailChartAdapter, [],
         [
           send_weekly_kills_chart_to_discord: fn _, _, _ ->
             {:ok, %{status_code: 200}}
           end
         ]},
        {KillmailChartScheduler, [:passthrough],
         [
           kill_charts_enabled?: fn -> true end
         ]}
      ]) do
        result = KillmailChartScheduler.execute(%{})
        assert {:ok, {:ok, %{status_code: 200}}, %{}} = result
      end
    end

    test "skips execution on non-Sunday days" do
      # Mock Date.utc_today to return a Monday (day 1)
      with_mocks([
        {Date, [], [utc_today: fn -> ~D[2023-01-02] end, day_of_week: fn _ -> 1 end]},
        {KillmailChartScheduler, [:passthrough],
         [
           kill_charts_enabled?: fn -> true end
         ]}
      ]) do
        result = KillmailChartScheduler.execute(%{})
        assert {:ok, :skipped, %{}} = result
      end
    end

    test "handles errors when sending chart" do
      # Mock Date.utc_today to return a Sunday (day 7)
      with_mocks([
        {Date, [], [utc_today: fn -> ~D[2023-01-01] end, day_of_week: fn _ -> 7 end]},
        {Config, [],
         [
           discord_channel_id_for: fn :kill_charts -> "123456789" end,
           kill_charts_enabled?: fn -> true end
         ]},
        {KillmailChartAdapter, [],
         [
           send_weekly_kills_chart_to_discord: fn _, _, _ ->
             {:error, "Failed to generate chart"}
           end
         ]},
        {KillmailChartScheduler, [:passthrough],
         [
           kill_charts_enabled?: fn -> true end
         ]}
      ]) do
        result = KillmailChartScheduler.execute(%{})
        assert {:error, "Failed to generate chart", %{}} = result
      end
    end

    test "handles exceptions when sending chart" do
      # Mock Date.utc_today to return a Sunday (day 7)
      with_mocks([
        {Date, [], [utc_today: fn -> ~D[2023-01-01] end, day_of_week: fn _ -> 7 end]},
        {Config, [],
         [
           discord_channel_id_for: fn :kill_charts -> "123456789" end,
           kill_charts_enabled?: fn -> true end
         ]},
        {KillmailChartAdapter, [],
         [
           send_weekly_kills_chart_to_discord: fn _, _, _ ->
             raise "Test exception"
           end
         ]},
        {KillmailChartScheduler, [:passthrough],
         [
           kill_charts_enabled?: fn -> true end
         ]}
      ]) do
        result = KillmailChartScheduler.execute(%{})
        assert {:error, "Test exception", %{}} = result
      end
    end
  end

  describe "kill_charts_enabled?/0" do
    test "returns true when kill charts is enabled" do
      # Mock Config.kill_charts_enabled? to return true
      with_mock(Config, [], kill_charts_enabled?: fn -> true end) do
        assert KillmailChartScheduler.kill_charts_enabled?() == true
      end
    end

    test "returns false when kill charts is disabled" do
      # Mock Config.kill_charts_enabled? to return false
      with_mock(Config, [], kill_charts_enabled?: fn -> false end) do
        assert KillmailChartScheduler.kill_charts_enabled?() == false
      end
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
