defmodule WandererNotifier.Config do
  @moduledoc """
  Proxy module for WandererNotifier.Core.Config.
  Delegates calls to the Core.Config implementation.
  """
  require Logger

  # Set up dynamic redirection for all function calls
  # This allows the proxy to automatically forward to the Core.Config module
  # without having to define each function individually

  # Get all functions from Core.Config module
  @target_module WandererNotifier.Core.Config

  # Get all functions in the target module and generate delegations for them
  @target_functions @target_module.__info__(:functions)
                    |> Enum.filter(fn {name, _arity} ->
                      # Skip module_info functions
                      name not in [:module_info]
                    end)

  # Generate proxy functions for each function in the target module
  for {function_name, arity} <- @target_functions do
    args = Macro.generate_arguments(arity, __MODULE__)

    @doc """
    Delegates to WandererNotifier.Core.Config.#{function_name}/#{arity}
    """
    def unquote(function_name)(unquote_splicing(args)) do
      apply(@target_module, unquote(function_name), [unquote_splicing(args)])
    end
  end

  # Nest the Timings module to maintain backward compatibility
  # Commenting out this module since it's duplicated in lib/wanderer_notifier/config/timings.ex
  # defmodule Timings do
  #   @moduledoc """
  #   Proxy module for WandererNotifier.Config.Timings.
  #   """

  #   @target_module WandererNotifier.Config.Timings

  #   # Get all functions in the target module and generate delegations for them
  #   @target_functions @target_module.__info__(:functions)
  #                     |> Enum.filter(fn {name, _arity} ->
  #                          # Skip module_info functions
  #                          name not in [:module_info]
  #                        end)

  #   # Generate proxy functions for each function in the target module
  #   for {function_name, arity} <- @target_functions do
  #     args = Macro.generate_arguments(arity, __MODULE__)

  #     @doc """
  #     Delegates to WandererNotifier.Core.Config.Timings.#{function_name}/#{arity}
  #     """
  #     def unquote(function_name)(unquote_splicing(args)) do
  #       apply(@target_module, unquote(function_name), [unquote_splicing(args)])
  #     end
  #   end
  # end
end
