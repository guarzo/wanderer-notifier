defmodule WandererNotifier.Adapters.KillmailChartAdapter do
  @moduledoc """
  Adapter for sending killmail charts to Discord.
  Handles the communication with the chart service and Discord integration.
  """

  @behaviour WandererNotifier.Adapters.KillmailChartAdapterBehaviour

  alias WandererNotifier.ChartService.KillmailChartAdapter

  @impl true
  def send_weekly_kills_chart_to_discord(channel_id, date_from, date_to) do
    KillmailChartAdapter.send_weekly_kills_chart_to_discord(channel_id, date_from, date_to)
  end
end
