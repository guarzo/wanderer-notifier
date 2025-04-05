defmodule WandererNotifier.Schedulers.KillmailChartSchedulerTest do
  use ExUnit.Case, async: false
  import Mox

  alias WandererNotifier.MockConfig
  alias WandererNotifier.MockDate
  alias WandererNotifier.MockKillmailChartAdapter, as: ChartAdapter
  alias WandererNotifier.MockNotifierFactory
  alias WandererNotifier.Schedulers.KillmailChartScheduler

  setup :verify_on_exit!
  setup :set_mox_from_context

  setup do
    # Default stubs
    stub(MockConfig, :kill_charts_enabled?, fn -> true end)
    stub(MockConfig, :discord_channel_id_for, fn _type -> "123456789" end)
    # Default to Monday
    stub(MockDate, :utc_today, fn -> ~D[2024-03-25] end)

    # Configure application environment for dependency injection
    Application.put_env(:wanderer_notifier, :killmail_chart_adapter, ChartAdapter)
    Application.put_env(:wanderer_notifier, :config_module, MockConfig)
    Application.put_env(:wanderer_notifier, :date_module, MockDate)
    Application.put_env(:wanderer_notifier, :notifier_factory, MockNotifierFactory)

    stub(MockDate, :day_of_week, fn date ->
      case Date.day_of_week(date) do
        # Monday
        1 -> 1
        # Sunday
        7 -> 7
        # Default to Tuesday for other cases
        _ -> 2
      end
    end)

    stub(ChartAdapter, :generate_weekly_kills_chart, fn ->
      {:ok, "http://example.com/chart.png"}
    end)

    :ok
  end

  describe "handle_info(:execute, state)" do
    test "executes on Sunday" do
      sunday = ~D[2024-03-24]
      expect(MockConfig, :kill_charts_enabled?, fn -> true end)
      expect(MockConfig, :discord_channel_id_for, fn :kill_charts -> "123456789" end)

      expect(ChartAdapter, :generate_weekly_kills_chart, fn ->
        {:ok, "http://example.com/chart.png"}
      end)

      expect(MockDate, :utc_today, fn -> sunday end)

      expect(MockNotifierFactory, :notify, fn :send_discord_file,
                                              [
                                                "http://example.com/chart.png",
                                                "weekly_kills.png",
                                                %{
                                                  title: "Weekly Kill Charts",
                                                  description: "Here are the weekly kill charts!"
                                                }
                                              ] ->
        {:ok, %{status_code: 200}}
      end)

      assert {:noreply, state} = KillmailChartScheduler.handle_info(:execute, %{last_run: nil})

      assert {:ok, %{status_code: 200}, %{}} = state.last_result
    end

    test "skips execution on non-Sunday" do
      monday = ~D[2024-03-25]
      expect(MockDate, :utc_today, fn -> monday end)
      assert {:noreply, state} = KillmailChartScheduler.handle_info(:execute, %{last_run: nil})
      assert {:ok, :skipped, %{}} = state.last_result
    end

    test "handles error when sending charts" do
      sunday = ~D[2024-03-24]
      expect(MockConfig, :kill_charts_enabled?, fn -> true end)
      expect(MockConfig, :discord_channel_id_for, fn :kill_charts -> "123456789" end)
      expect(ChartAdapter, :generate_weekly_kills_chart, fn -> {:error, :some_error} end)
      expect(MockDate, :utc_today, fn -> sunday end)

      assert {:noreply, state} = KillmailChartScheduler.handle_info(:execute, %{last_run: nil})

      assert {:error, "Failed to generate weekly kills chart: some_error", %{}} =
               state.last_result
    end

    test "skips when kill charts are disabled" do
      sunday = ~D[2024-03-24]
      expect(MockConfig, :kill_charts_enabled?, fn -> false end)
      expect(MockDate, :utc_today, fn -> sunday end)
      assert {:noreply, state} = KillmailChartScheduler.handle_info(:execute, %{last_run: nil})
      assert {:ok, :skipped, %{}} = state.last_result
    end

    test "handles error when sending notification" do
      sunday = ~D[2024-03-24]
      expect(MockConfig, :kill_charts_enabled?, fn -> true end)
      expect(MockConfig, :discord_channel_id_for, fn :kill_charts -> "123456789" end)

      expect(ChartAdapter, :generate_weekly_kills_chart, fn ->
        {:ok, "http://example.com/chart.png"}
      end)

      expect(MockDate, :utc_today, fn -> sunday end)

      expect(MockNotifierFactory, :notify, fn :send_discord_file,
                                              [
                                                "http://example.com/chart.png",
                                                "weekly_kills.png",
                                                %{
                                                  title: "Weekly Kill Charts",
                                                  description: "Here are the weekly kill charts!"
                                                }
                                              ] ->
        {:error,
         %Nostrum.Error.ApiError{
           status_code: 400,
           response: %{
             code: 50_035,
             message: "Invalid Form Body",
             errors: %{
               embeds: %{
                 "0" => %{
                   description: %{
                     _errors: [%{code: "BASE_TYPE_REQUIRED", message: "This field is required"}]
                   }
                 }
               }
             }
           }
         }}
      end)

      assert {:noreply, state} = KillmailChartScheduler.handle_info(:execute, %{last_run: nil})

      assert {:error, "Failed to send chart: Failed to send notification", %{}} =
               state.last_result
    end
  end

  describe "kill_charts_enabled?/0" do
    test "returns true when kill charts is enabled" do
      expect(MockConfig, :kill_charts_enabled?, fn -> true end)
      assert KillmailChartScheduler.kill_charts_enabled?() == true
    end

    test "returns false when kill charts is disabled" do
      expect(MockConfig, :kill_charts_enabled?, fn -> false end)
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
