defmodule WandererNotifier.TPSChartScheduler do
  @moduledoc """
  Proxy module for WandererNotifier.Services.TPSChartScheduler.
  Delegates calls to the Services.TPSChartScheduler implementation.
  """

  @doc """
  Trigger the chart scheduler to send charts now
  Delegates to WandererNotifier.Services.TPSChartScheduler.send_charts_now/0
  """
  def send_charts_now do
    WandererNotifier.Services.TPSChartScheduler.send_charts_now()
  end

  @doc """
  Returns the child_spec for this service
  """
  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {WandererNotifier.Services.TPSChartScheduler, :start_link, [opts]},
      type: :worker,
      restart: :permanent,
      shutdown: 500
    }
  end
end
