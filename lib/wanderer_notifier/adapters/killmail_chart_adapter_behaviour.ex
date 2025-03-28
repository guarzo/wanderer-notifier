defmodule WandererNotifier.Adapters.KillmailChartAdapterBehaviour do
  @moduledoc """
  Behaviour for the killmail chart adapter.
  Defines the contract for sending weekly kill charts to Discord.
  """

  @callback send_weekly_kills_chart_to_discord(
              channel_id :: String.t(),
              date_from :: Date.t(),
              date_to :: Date.t()
            ) :: {:ok, map()} | {:error, term()}
end
