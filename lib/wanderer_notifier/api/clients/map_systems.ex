defmodule WandererNotifier.Api.Clients.MapSystems do
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
end
