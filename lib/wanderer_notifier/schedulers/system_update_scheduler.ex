defmodule WandererNotifier.Schedulers.SystemUpdateScheduler do
  @moduledoc """
  Scheduler for updating system information.
  """

  use GenServer
  alias WandererNotifier.Api.Map.SystemsClient
  alias WandererNotifier.Core.Features

  @doc """
  Starts the scheduler.
  """
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
  Executes the system update task.
  """
  def execute(cached_systems \\ []) do
    if Features.map_charts_enabled?() do
      case SystemsClient.update_systems(cached_systems) do
        {:ok, systems} -> {:ok, systems}
        error -> error
      end
    else
      {:error, :feature_disabled}
    end
  end
end
