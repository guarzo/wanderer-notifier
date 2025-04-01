defmodule WandererNotifier.MockKillmailChartAdapter do
  @moduledoc """
  Mock implementation of KillmailChartAdapter for testing.
  """
  @behaviour WandererNotifier.ChartService.KillmailChartAdapterBehaviour

  @impl true
  def generate_weekly_kills_chart do
    {:ok, "https://example.com/mock-chart.png"}
  end
end
