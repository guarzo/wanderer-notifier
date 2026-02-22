defmodule WandererNotifier.Shared.Dependencies do
  @moduledoc """
  Lightweight function-based dependency injection module.

  Centralizes Application.get_env lookups for injectable modules, making
  it easy to override dependencies in tests via Application.put_env/3.

  ## Usage

      alias WandererNotifier.Shared.Dependencies

      # In production code
      Dependencies.map_registry().all_maps()

      # In tests
      Application.put_env(:wanderer_notifier, :map_registry_module, MyMockRegistry)
  """

  @doc """
  Returns the configured MapRegistry module.

  Defaults to `WandererNotifier.Map.MapRegistry`.
  Override in tests via `Application.put_env(:wanderer_notifier, :map_registry_module, mock)`.
  """
  @spec map_registry() :: module()
  def map_registry do
    Application.get_env(
      :wanderer_notifier,
      :map_registry_module,
      WandererNotifier.Map.MapRegistry
    )
  end
end
