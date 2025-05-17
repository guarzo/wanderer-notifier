defmodule WandererNotifier.Schedulers.Registry do
  @moduledoc """
  Finds all modules under WandererNotifier.Schedulers that implement the behaviour.
  """

  @doc """
  Returns a list of all registered schedulers.
  """
  def all_schedulers do
    :code.all_loaded()
    |> Enum.filter(&scheduler_module?/1)
    |> Enum.map(&elem(&1, 0))
  end

  defp scheduler_module?({mod, _}) do
    excluded = [
      WandererNotifier.Schedulers.Supervisor,
      WandererNotifier.Schedulers.Registry
    ]

    mod_str = to_string(mod)

    String.contains?(mod_str, "Scheduler") and
      mod not in excluded and
      implements_behaviour?(mod, WandererNotifier.Schedulers.Scheduler)
  end

  defp implements_behaviour?(module, behaviour) do
    try do
      behaviours = module.module_info(:attributes)[:behaviour] || []
      behaviour in behaviours
    rescue
      _ -> false
    end
  end
end
