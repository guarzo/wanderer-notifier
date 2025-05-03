defmodule WandererNotifier.Schedulers.Supervisor do
  @moduledoc """
  Supervisor for all scheduler modules. Dynamically starts all discovered schedulers.
  """

  use Supervisor
  alias WandererNotifier.Schedulers.Registry

  def start_link(_opts \\ []) do
    Supervisor.start_link(__MODULE__, [], name: __MODULE__)
  end

  @impl true
  def init(_) do
    children =
      Registry.all_schedulers()
      |> Enum.map(&scheduler_child_spec/1)

    Supervisor.init(children, strategy: :one_for_one)
  end

  defp scheduler_child_spec(mod) do
    %{
      id: mod,
      start: {Task, :start_link, [fn -> start_scheduler(mod) end]},
      restart: :permanent
    }
  end

  def start_scheduler(mod) do
    %{type: type, spec: spec} = mod.config()

    case type do
      :interval ->
        :timer.send_interval(spec, {:run, mod})
        loop(mod)
    end
  end

  defp loop(mod) do
    receive do
      {:run, ^mod} ->
        execute(mod)
        loop(mod)
    end
  end

  defp execute(mod) do
    start = System.monotonic_time()
    case mod.run() do
      :ok ->
        :telemetry.execute([:wanderer_notifier, :scheduler, :success], %{}, %{module: mod})
      {:error, reason} ->
        :telemetry.execute([
          :wanderer_notifier, :scheduler, :failure
        ], %{}, %{module: mod, error: inspect(reason)})
    end
    duration = System.monotonic_time() - start
    :telemetry.execute([
      :wanderer_notifier, :scheduler, :duration
    ], %{duration: duration}, %{module: mod})
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
