defmodule WandererNotifier.Maintenance.Scheduler do
  @moduledoc """
  Proxy module that delegates to Scheduler.
  """
  require Logger
  alias WandererNotifier.Services.Maintenance.Scheduler

  @doc """
  Performs periodic maintenance tasks by delegating to
  Scheduler.tick/1.
  """
  def tick(state) do
    Scheduler.tick(state)
  end

  @doc """
  Performs initial checks when the service starts by delegating to
  Scheduler.do_initial_checks/1.
  """
  def do_initial_checks(state) do
    Scheduler.do_initial_checks(state)
  end
end
