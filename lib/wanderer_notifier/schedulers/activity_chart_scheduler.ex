defmodule WandererNotifier.Schedulers.ActivityChartScheduler do
  @moduledoc """
  Scheduler for activity chart generation.
  """

  use GenServer
  alias WandererNotifier.ChartService.ActivityChartAdapter
  alias WandererNotifier.Core.Features

  @doc """
  Starts the scheduler with the given options.
  """
  def start_link(opts \\ [])

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Initializes the scheduler state.
  """
  @impl true
  def init(opts) do
    {:ok, opts}
  end

  @doc """
  Executes the activity chart update task.
  """
  def execute(_state) do
    if Features.activity_charts_enabled?() do
      ActivityChartAdapter.update_activity_charts()
    else
      {:error, :feature_disabled}
    end
  end
end
