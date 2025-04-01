defmodule WandererNotifier.ChartService.KillmailChartAdapterBehaviour do
  @moduledoc """
  Behaviour for the killmail chart adapter.
  Defines the contract for generating and sending killmail charts.
  """

  @doc """
  Generates a chart showing the top characters by kills for the past week.
  Returns {:ok, chart_url} if successful, {:error, reason} if chart generation fails.
  """
  @callback generate_weekly_kills_chart() :: {:ok, String.t()} | {:error, term()}

  @doc """
  Sends a weekly kills chart to Discord.
  Returns {:ok, message_id} if successful, {:error, reason} if sending fails.
  """
  @callback send_weekly_kills_chart_to_discord(String.t(), String.t(), String.t()) ::
              {:ok, String.t()} | {:error, term()}
end
