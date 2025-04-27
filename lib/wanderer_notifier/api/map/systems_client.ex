defmodule WandererNotifier.Api.Map.SystemsClient do
  @moduledoc """
  Client for retrieving and processing system data from the map API.
  Uses structured data types and consistent parsing to simplify the logic.

  @deprecated Use WandererNotifier.Map.SystemsClient instead
  """
  alias WandererNotifier.HttpClient.Httpoison, as: HttpClient
  alias WandererNotifier.Api.Map.SystemStaticInfo
  alias WandererNotifier.Api.Map.UrlBuilder
  alias WandererNotifier.Config.Config
  alias WandererNotifier.Config.Features
  alias WandererNotifier.Data.Cache.Helpers, as: CacheHelpers
  alias WandererNotifier.Data.Cache.Keys, as: CacheKeys
  alias WandererNotifier.Cache.Repository, as: CacheRepo
  alias WandererNotifier.Data.MapSystem
  alias WandererNotifier.Logger.Logger, as: AppLogger
  alias WandererNotifier.Notifiers.Factory
  alias WandererNotifier.Notifiers.StructuredFormatter
  alias WandererNotifier.Cache.Helpers, as: CacheHelpers
  alias WandererNotifier.Cache.Keys, as: CacheKeys

  @doc """
  Updates the systems in the cache.

  If cached_systems is provided, it will also identify and notify about new systems.

  ## Parameters
    - cached_systems: Optional list of cached systems for comparison

  ## Returns
    - {:ok, systems} on success
    - {:error, reason} on failure
  """
  def update_systems(cached_systems \\ nil) do
    # This function delegates to the new implementation
    WandererNotifier.Map.SystemsClient.update_systems(cached_systems)
  end

  # The rest of the functions in this module are no longer used
  # Consider removing them in a future update
  # ... existing code ...
end
