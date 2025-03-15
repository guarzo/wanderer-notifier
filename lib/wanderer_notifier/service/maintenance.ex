defmodule WandererNotifier.Service.Maintenance do
  @moduledoc """
  Coordinates periodic maintenance tasks:
    - Logging status messages
    - Updating systems and characters
    - Checking backup kills
  """
  require Logger
  alias WandererNotifier.Maintenance.Scheduler

  @spec do_periodic_checks(map()) :: map()
  def do_periodic_checks(state) do
    Scheduler.do_periodic_checks(state)
  end

  @spec do_initial_checks(map()) :: map()
  def do_initial_checks(state) do
    Logger.info("[Maintenance] Running initial startup checks")
    try do
      Scheduler.do_initial_checks(state)
    rescue
      e ->
        Logger.error("[Maintenance] Error during initial checks: #{inspect(e)}")
        Logger.error("[Maintenance] Stacktrace: #{inspect(Process.info(self(), :current_stacktrace))}")
        # Return the original state if checks fail
        state
    end
  end
end
