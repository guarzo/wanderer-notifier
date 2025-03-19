defmodule WandererNotifier.SystemTracker do
  @moduledoc """
  Proxy module for WandererNotifier.Services.SystemTracker.
  This module delegates calls to the underlying service implementation.
  """

  require Logger

  @doc """
  Updates the system list and notifies about new systems.
  Delegates to WandererNotifier.Services.SystemTracker.update_systems/1.
  """
  def update_systems(cached_systems \\ nil) do
    # Validate cached_systems before delegation
    validated_systems = validate_cached_systems(cached_systems)
    WandererNotifier.Services.SystemTracker.update_systems(validated_systems)
  end

  # Helper function to validate cached_systems parameter
  defp validate_cached_systems(nil), do: nil

  defp validate_cached_systems(systems) when is_list(systems) do
    if Enum.all?(systems, &is_map/1) do
      systems
    else
      Logger.warning(
        "[SystemTracker] Invalid cached_systems format: expected list of maps, got: #{inspect(systems)}"
      )

      # Return empty list as a safe fallback
      []
    end
  end

  defp validate_cached_systems(invalid) do
    Logger.warning(
      "[SystemTracker] Invalid cached_systems type: expected list or nil, got: #{inspect(invalid)}"
    )

    nil
  end
end
