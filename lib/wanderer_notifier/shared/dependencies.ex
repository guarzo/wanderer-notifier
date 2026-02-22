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

  @doc """
  Returns the configured MapTrackingClient module.

  Defaults to `WandererNotifier.Domains.Tracking.MapTrackingClient`.
  Override in tests via `Application.put_env(:wanderer_notifier, :map_tracking_client_module, mock)`.
  """
  @spec map_tracking_client() :: module()
  def map_tracking_client do
    Application.get_env(
      :wanderer_notifier,
      :map_tracking_client_module,
      WandererNotifier.Domains.Tracking.MapTrackingClient
    )
  end
end
