defmodule WandererNotifier.ChartService.KillmailChartAdapterBehaviour do
  @moduledoc """
  Behaviour definition for killmail chart adapter.
  Defines the contract that any implementation must fulfill.
  """

  @doc """
  Sends a weekly kills chart to Discord for a specified date range.

  ## Parameters
  - `channel_id`: The Discord channel ID to send the chart to
  - `date_from`: The start date for the chart data
  - `date_to`: The end date for the chart data

  ## Returns
  - `{:ok, map()}`: The response from Discord after sending the chart
  - `{:error, term()}`: If an error occurred during chart generation or sending
  """
  @callback send_weekly_kills_chart_to_discord(
              channel_id :: String.t(),
              date_from :: Date.t(),
              date_to :: Date.t()
            ) :: {:ok, map()} | {:error, term()}
end
