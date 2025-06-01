defmodule WandererNotifier.Schedulers.Supervisor do
  @moduledoc """
  Supervisor for all scheduler modules.
  """

  use Supervisor
  require Logger
  alias WandererNotifier.Logger.Logger, as: AppLogger

  @scheduler_modules [
    WandererNotifier.Schedulers.SystemUpdateScheduler,
    WandererNotifier.Schedulers.CharacterUpdateScheduler,
    WandererNotifier.Schedulers.ServiceStatusScheduler
  ]

  def start_link(_opts \\ []) do
    AppLogger.scheduler_info("Starting scheduler supervisor")
    Supervisor.start_link(__MODULE__, [], name: __MODULE__)
  end

  @impl true
  def init(_) do
    # Only start schedulers if enabled
    schedulers_enabled = Application.get_env(:wanderer_notifier, :schedulers_enabled, false)
    AppLogger.scheduler_info("Schedulers enabled: #{schedulers_enabled}")

    if schedulers_enabled do
      children = @scheduler_modules

      AppLogger.scheduler_info("Starting scheduler children",
        children: inspect(children)
      )

      Supervisor.init(children,
        strategy: :one_for_one,
        max_restarts: 5,
        max_seconds: 60
      )
    else
      # Return empty children list if schedulers are disabled
      AppLogger.scheduler_info("Schedulers disabled, starting with empty children list")
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

  @doc """
  Returns a list of all running schedulers.
  """
  def running_schedulers do
    @scheduler_modules
    |> Enum.map(&{&1, running?(&1)})
    |> Enum.filter(fn {_module, running} -> running end)
    |> Enum.map(fn {module, _} -> module end)
  end

  @doc """
  Returns the status of all schedulers.
  """
  def scheduler_status do
    running = running_schedulers()

    for scheduler <- @scheduler_modules do
      status =
        if scheduler in running do
          :running
        else
          :stopped
        end

      {scheduler, status}
    end
  end

  defp running?(module) do
    case Process.whereis(module) do
      nil -> false
      pid when is_pid(pid) -> Process.alive?(pid)
    end
  end
end
