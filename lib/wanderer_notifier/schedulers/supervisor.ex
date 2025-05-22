defmodule WandererNotifier.Schedulers.Supervisor do
  @moduledoc """
  Supervisor for all scheduler modules.
  """

  use Supervisor
  require Logger

  def start_link(_opts \\ []) do
    Logger.info("Starting scheduler supervisor")
    Supervisor.start_link(__MODULE__, [], name: __MODULE__)
  end

  @impl true
  def init(_) do
    # Only start schedulers if enabled
    schedulers_enabled = Application.get_env(:wanderer_notifier, :schedulers_enabled, false)
    Logger.info("Schedulers enabled: #{schedulers_enabled}")

    if schedulers_enabled do
      children = [
        {WandererNotifier.Schedulers.SystemUpdateScheduler, []},
        {WandererNotifier.Schedulers.CharacterUpdateScheduler, []},
        {WandererNotifier.Schedulers.ServiceStatusScheduler, []}
      ]

      Logger.info("Starting scheduler children: #{inspect(children)}")
      {:ok, _} = Supervisor.init(children, strategy: :one_for_one)
    else
      # Return empty children list if schedulers are disabled
      Logger.info("Schedulers disabled, starting with empty children list")
      {:ok, _} = Supervisor.init([], strategy: :one_for_one)
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
