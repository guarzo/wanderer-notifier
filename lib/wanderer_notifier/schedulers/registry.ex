defmodule WandererNotifier.Schedulers.Registry do
  @moduledoc """
  Finds all modules under WandererNotifier.Schedulers that implement the behaviour.
  """

  def all_schedulers do
    :application.get_key(:wanderer_notifier, :modules)
    |> elem(1)
    |> Enum.filter(&String.starts_with?(Atom.to_string(&1), "Elixir.WandererNotifier.Schedulers."))
    |> Enum.filter(&implements_scheduler?/1)
  end

  defp implements_scheduler?(mod) do
    behaviours = mod.module_info(:attributes)[:behaviour] || []
    WandererNotifier.Schedulers.Scheduler in behaviours
  end
end
