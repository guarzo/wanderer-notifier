defmodule WandererNotifier.ChartService.KillmailChartAdapterTest do
  use ExUnit.Case, async: false
  import Mock

  alias WandererNotifier.ChartService.KillmailChartAdapter
  alias WandererNotifier.ChartService.ChartService
  alias WandererNotifier.Resources.Character

  # Mock data
  @test_characters [
    %Character{id: 1, name: "Character 1"},
    %Character{id: 2, name: "Character 2"},
    %Character{id: 3, name: "Character 3"}
  ]

  @test_weekly_stats [
    %{
      character_id: 1,
      week: ~D[2023-01-01],
      kills: 10,
      losses: 2,
      damage_dealt: 5000,
      damage_received: 1000,
      final_blows: 5
    },
    %{
      character_id: 2,
      week: ~D[2023-01-01],
      kills: 5,
      losses: 1,
      damage_dealt: 3000,
      damage_received: 500,
      final_blows: 2
    },
    %{
      character_id: 3,
      week: ~D[2023-01-01],
      kills: 15,
      losses: 0,
      damage_dealt: 7000,
      damage_received: 200,
      final_blows: 8
    }
  ]

  @discord_response {:ok, %{status_code: 200}}

  describe "generate_weekly_kills_chart/1" do
    test "returns a chart URL on success" do
      with_mocks([
        {KillmailChartAdapter, [:passthrough],
         [
           get_tracked_characters: fn -> @test_characters end,
           get_weekly_stats: fn _ -> @test_weekly_stats end
         ]},
        {ChartService, [], [generate_chart_url: fn _ -> {:ok, "https://chart.url"} end]}
      ]) do
        result = KillmailChartAdapter.generate_weekly_kills_chart(%{limit: 20})
        assert {:ok, "https://chart.url"} = result
      end
    end

    test "returns error when chart generation fails" do
      with_mocks([
        {KillmailChartAdapter, [:passthrough],
         [
           get_tracked_characters: fn -> @test_characters end,
           get_weekly_stats: fn _ -> @test_weekly_stats end
         ]},
        {ChartService, [], [generate_chart_url: fn _ -> {:error, "Chart error"} end]}
      ]) do
        result = KillmailChartAdapter.generate_weekly_kills_chart(%{limit: 20})
        assert {:error, "Chart error"} = result
      end
    end

    test "returns error when no characters are found" do
      with_mock KillmailChartAdapter, [:passthrough], get_tracked_characters: fn -> [] end do
        result = KillmailChartAdapter.generate_weekly_kills_chart(%{limit: 20})
        assert {:error, "No tracked characters found"} = result
      end
    end

    test "returns error when no stats are found" do
      with_mocks([
        {KillmailChartAdapter, [:passthrough],
         [
           get_tracked_characters: fn -> @test_characters end,
           get_weekly_stats: fn _ -> [] end
         ]}
      ]) do
        result = KillmailChartAdapter.generate_weekly_kills_chart(%{limit: 20})
        assert {:error, "No weekly statistics found for tracked characters"} = result
      end
    end
  end

  describe "send_weekly_kills_chart_to_discord/4" do
    test "sends chart to Discord successfully" do
      with_mocks([
        {KillmailChartAdapter, [:passthrough],
         [generate_weekly_kills_chart: fn _ -> {:ok, "https://chart.url"} end]},
        {ChartService, [], [send_chart_to_discord: fn _, _, _, _ -> @discord_response end]}
      ]) do
        result =
          KillmailChartAdapter.send_weekly_kills_chart_to_discord(
            "Test Title",
            "Test Description",
            "123456789"
          )

        assert result == @discord_response
      end
    end

    test "returns error when chart generation fails" do
      with_mock KillmailChartAdapter, [:passthrough],
        generate_weekly_kills_chart: fn _ -> {:error, "Chart generation failed"} end do
        result =
          KillmailChartAdapter.send_weekly_kills_chart_to_discord(
            "Test Title",
            "Test Description",
            "123456789"
          )

        assert {:error, "Chart generation failed"} = result
      end
    end
  end

  describe "helpers" do
    test "get_top_characters_by_kills/2 returns top N characters" do
      stats = @test_weekly_stats
      top_stats = KillmailChartAdapter.get_top_characters_by_kills(stats, 2)

      assert length(top_stats) == 2
      # Character with 15 kills
      assert hd(top_stats).character_id == 3
      # Character with 10 kills
      assert Enum.at(top_stats, 1).character_id == 1
    end

    test "extract_kill_metrics/1 correctly extracts metrics" do
      stats = @test_weekly_stats
      metrics = KillmailChartAdapter.extract_kill_metrics(stats)

      assert metrics == [
               %{character_id: 1, name: "Character 1", kills: 10},
               %{character_id: 2, name: "Character 2", kills: 5},
               %{character_id: 3, name: "Character 3", kills: 15}
             ]
    end
  end
end
