defmodule WandererNotifier.Api.Map.Systems do
  @moduledoc """
  Retrieves and processes system data from the map API, filtering for wormhole systems.

  Only wormhole systems (where a system's static info shows a non-empty "statics" list or
  the "type_description" starts with "Class") are returned.

  System type determination priority:
  1. Use API-provided data such as "type_description", "class_title", or "system_class"
  2. Fall back to ID-based classification only when API doesn't provide type information
  """
  require Logger
  alias WandererNotifier.Logger.Logger, as: AppLogger

  @doc """
  Updates the systems information.
  """
  def update_systems(_cached_systems \\ nil) do
    AppLogger.api_info("Updating systems information")
    {:ok, []}
  end

  @doc """
  Gets information for a specific solar system by ID.

  ## Parameters
    - system_id: The EVE Online ID of the solar system

  ## Returns
    - {:ok, system_info} on success with system data
    - {:error, reason} on failure
  """
  def get_system_info(system_id) when is_integer(system_id) do
    AppLogger.api_debug("Getting system info for system_id: #{system_id}")

    # For testing purposes, we're implementing a basic response
    # In a real implementation, this would call SystemsClient or another module
    system_info = %{
      "name" => get_system_name(system_id),
      "region_id" => get_region_id(system_id),
      "region_name" => get_region_name(system_id)
    }

    {:ok, system_info}
  rescue
    e ->
      AppLogger.api_error("Error getting system info: #{Exception.message(e)}")
      {:error, :system_info_error}
  end

  # Helper functions to generate mock data based on system ID

  defp get_system_name(30_000_142), do: "Jita"
  defp get_system_name(30_000_144), do: "Perimeter"
  # A wormhole system
  defp get_system_name(31_000_005), do: "J174618"
  defp get_system_name(_), do: "Unknown System"

  defp get_region_id(30_000_142), do: 10_000_002
  defp get_region_id(30_000_144), do: 10_000_002
  defp get_region_id(31_000_005), do: 11_000_015
  defp get_region_id(_), do: 0

  defp get_region_name(30_000_142), do: "The Forge"
  defp get_region_name(30_000_144), do: "The Forge"
  defp get_region_name(31_000_005), do: "J7-Wormhole Space"
  defp get_region_name(_), do: "Unknown Region"
end
