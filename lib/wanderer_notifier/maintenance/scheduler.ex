defmodule WandererNotifier.Maintenance.Scheduler do
  @moduledoc """
  Proxy module that delegates to WandererNotifier.Services.Maintenance.Scheduler.
  """
  require Logger

  @doc """
  Performs periodic maintenance tasks by delegating to
  WandererNotifier.Services.Maintenance.Scheduler.tick/1.
  """
  def tick(state) do
    WandererNotifier.Services.Maintenance.Scheduler.tick(state)
  end

  @doc """
  Performs initial checks when the service starts by delegating to
  WandererNotifier.Services.Maintenance.Scheduler.do_initial_checks/1.
  """
  def do_initial_checks(state) do
    WandererNotifier.Services.Maintenance.Scheduler.do_initial_checks(state)
  end
end
