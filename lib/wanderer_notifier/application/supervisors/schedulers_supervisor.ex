defmodule WandererNotifier.Application.Supervisors.Schedulers.Supervisor do
  @moduledoc """
  Supervisor for all scheduler modules.
  """

  use Supervisor
  require Logger

  alias WandererNotifier.Shared.Config

  def start_link(_opts \\ []) do
    Logger.info("Starting scheduler supervisor")
    Supervisor.start_link(__MODULE__, [], name: __MODULE__)
  end

  @impl true
  def init(_) do
    # Only start schedulers if enabled
    schedulers_enabled = Config.schedulers_enabled?()
    Logger.info("Schedulers enabled: #{schedulers_enabled}")

    if schedulers_enabled do
      children = [
        # Only keep non-polling schedulers
        {WandererNotifier.Schedulers.ServiceStatusScheduler, []}
      ]

      Logger.info("Starting #{length(children)} scheduler(s): ServiceStatusScheduler")
      Supervisor.init(children, strategy: :one_for_one)
    else
      # Return empty children list if schedulers are disabled
      Logger.info("Schedulers disabled, starting with empty children list")
      Supervisor.init([], strategy: :one_for_one)
    end
  end

  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      type: :supervisor,
      restart: :permanent,
      shutdown: 500
    }
  end
end
