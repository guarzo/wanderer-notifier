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
end
