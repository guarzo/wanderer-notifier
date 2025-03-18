defmodule WandererNotifier.SystemTracker do
  @moduledoc """
  Proxy module for WandererNotifier.Services.SystemTracker.
  This module delegates calls to the underlying service implementation.
  """

  @doc """
  Updates the system list and notifies about new systems.
  Delegates to WandererNotifier.Services.SystemTracker.update_systems/1.
  """
  def update_systems(cached_systems \\ nil) do
    WandererNotifier.Services.SystemTracker.update_systems(cached_systems)
  end
end
