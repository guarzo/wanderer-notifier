defmodule WandererNotifier.Schedulers.Registry do
  @moduledoc """
  Finds all modules under WandererNotifier.Schedulers that implement the behaviour.
  """

  require Logger

  @doc """
  Returns a list of all registered schedulers.
  """
  def all_schedulers do
    loaded_modules = :code.all_loaded()
    Logger.debug("All loaded modules: #{inspect(loaded_modules)}")

    schedulers =
      for {mod, _path} = module_info <- loaded_modules,
          scheduler_module?(module_info) do
        mod
      end

    Logger.info("Discovered schedulers: #{inspect(schedulers)}")
    schedulers
  end

  defp scheduler_module?({mod, _}) do
    excluded = [
      WandererNotifier.Schedulers.Supervisor,
      WandererNotifier.Schedulers.Registry,
      WandererNotifier.Schedulers.BaseMapScheduler
    ]

    mod_str = to_string(mod)
    is_scheduler = String.contains?(mod_str, "Scheduler") and mod not in excluded

    # Check if the module uses BaseMapScheduler
    uses_base =
      try do
        Code.ensure_loaded?(mod) and
          mod.__info__(:attributes)
          |> Keyword.get(:__using__, [])
          |> Enum.any?(fn {module, _} ->
            module == WandererNotifier.Schedulers.BaseMapScheduler
          end)
      rescue
        _ -> false
      end

    Logger.debug("Checking module #{mod}: is_scheduler=#{is_scheduler}, uses_base=#{uses_base}")
    is_scheduler and uses_base
  end
end
