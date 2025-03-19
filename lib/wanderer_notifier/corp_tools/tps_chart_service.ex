defmodule WandererNotifier.CorpTools.TPSChartService do
  @moduledoc """
  Service for EVE TPS (Tranquility Player Stats) chart generation and delivery.

  This module provides functionality for creating charts based on TPS data from
  the EVE Corp Tools API, generating charts server-side using Node.js and Chart.js.

  ## Examples

  ```elixir
  # Create a TPS chart config
  config = TPSChartService.create_chart_config(:damage_final_blows)

  # Generate and deliver the chart to Discord
  TPSChartService.send_chart_to_discord(:damage_final_blows)
  ```
  """
end
