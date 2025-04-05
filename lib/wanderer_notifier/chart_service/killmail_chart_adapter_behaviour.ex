defmodule WandererNotifier.ChartService.KillmailChartAdapterBehaviour do
  @moduledoc """
  Behaviour for the killmail chart adapter.
  Defines the contract for generating and sending killmail charts.
  """

  @doc """
  Generates a chart showing the top characters by kills for the past week.
  Returns {:ok, chart_url} if successful, {:error, reason} if chart generation fails.
  """
  @callback generate_weekly_kills_chart() :: {:ok, binary()} | {:error, term()}

  @doc """
  Generates a chart showing the top characters by isk for the past week.
  Returns {:ok, chart_url} if successful, {:error, reason} if chart generation fails.
  """
  @callback generate_weekly_isk_chart(limit :: integer() | map()) ::
              {:ok, binary()} | {:error, term()}

  @doc """
  Generates a chart showing the kill validation for the past week.
  Returns {:ok, chart_url} if successful, {:error, reason} if chart generation fails.
  """
  @callback generate_kill_validation_chart() :: {:ok, binary()} | {:error, term()}

  @doc """
  Sends a weekly kills chart to Discord.
  Returns {:ok, message_id} if successful, {:error, reason} if sending fails.
  """
  @callback send_weekly_kills_chart_to_discord(
              channel_id :: String.t() | nil,
              date_from :: Date.t(),
              date_to :: Date.t()
            ) :: {:ok, term()} | {:error, term()}
end
