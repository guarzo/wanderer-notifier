defmodule WandererNotifier.Service.TPSChartScheduler do
  @moduledoc """
  Proxy module for WandererNotifier.Services.TPSChartScheduler.
  Delegates calls to the implementation in Services.
  """

  @doc """
  Sends TPS charts now.
  Delegates to WandererNotifier.Services.TPSChartScheduler.send_charts_now/0
  """
  def send_charts_now do
    WandererNotifier.Services.TPSChartScheduler.send_charts_now()
  end
end
