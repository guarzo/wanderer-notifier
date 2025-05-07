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
    mod |> to_string() |> String.contains?("Scheduler")
  end
end
