defmodule WandererNotifier.Map.Client do
  @moduledoc """
  Client for interacting with the Wanderer map API.

  This module provides a simplified facade over the specific client modules
  for different map API endpoints, handling feature checks and error management.
  """
  alias WandererNotifier.Map.CharactersClient
  alias WandererNotifier.Map.SystemsClient
  alias WandererNotifier.Config.Features
  alias WandererNotifier.Cache.Repository, as: CacheRepo
  alias WandererNotifier.Logger.Logger, as: AppLogger

  @doc """
  Updates system information from the map API.

  ## Returns
    - {:ok, systems} on success
    - {:error, reason} on failure
  """
  def update_systems do
    if Features.system_tracking_enabled?() do
      SystemsClient.update_systems()
    else
      AppLogger.api_debug("[Map.Client] System tracking disabled due to license restrictions")
      {:error, :feature_disabled}
    end
  rescue
    e ->
      AppLogger.api_error("[Map.Client] Error in update_systems: #{inspect(e)}")

      AppLogger.api_error(
        "[Map.Client] Stacktrace: #{inspect(Process.info(self(), :current_stacktrace))}"
      )

      {:error, {:exception, e}}
  end

  @doc """
  Updates system information from the map API, comparing with cached systems.

  ## Parameters
    - cached_systems: List of previously cached systems for comparison

  ## Returns
    - {:ok, systems} on success
    - {:error, reason} on failure
  """
  def update_systems_with_cache(cached_systems) do
    if Features.system_tracking_enabled?() do
      # Updated to work with new SystemsClient module that returns MapSystem structs
      case SystemsClient.update_systems(cached_systems) do
        {:ok, systems} -> {:ok, systems}
        error -> error
      end
    else
      AppLogger.api_debug("[Map.Client] System tracking disabled due to license restrictions")
      {:error, :feature_disabled}
    end
  rescue
    e ->
      AppLogger.api_error("[Map.Client] Error in update_systems_with_cache: #{inspect(e)}")

      AppLogger.api_error(
        "[Map.Client] Stacktrace: #{inspect(Process.info(self(), :current_stacktrace))}"
      )

      {:error, {:exception, e}}
  end

  @doc """
  Updates tracked character information from the map API.

  ## Parameters
    - cached_characters: Optional list of cached characters for comparison

  ## Returns
    - {:ok, characters} on success
    - {:error, reason} on failure
  """
  def update_tracked_characters(cached_characters \\ nil) do
    AppLogger.api_debug("Starting character update")

    # Use provided cached_characters if available, otherwise get from cache
    # Normalize to an empty list if nil
    current_characters = cached_characters || CacheRepo.get("map:characters") || []

    # Ensure we're dealing with a list (handle different types of input)
    current_characters_list = ensure_list(current_characters)

    # Delegate to the CharactersClient which returns {:ok, characters} or {:error, reason}
    result = CharactersClient.update_tracked_characters(current_characters_list)
    result
  end

  # Helper function to ensure we're working with a list
  defp ensure_list(nil), do: []
  defp ensure_list(list) when is_list(list), do: list
  defp ensure_list({:ok, list}) when is_list(list), do: list
  defp ensure_list(_), do: []

  @doc """
  Retrieves character activity data from the map API.

  ## Parameters
    - slug: Optional map slug override

  ## Returns
    - {:ok, data} on success
    - {:error, reason} on failure
  """
  def get_character_activity(slug \\ nil) do
    if Features.map_charts_enabled?() do
      CharactersClient.get_character_activity(slug)
    else
      AppLogger.api_debug("[Map.Client] Map charts disabled due to license restrictions")
      {:error, :feature_disabled}
    end
  rescue
    e ->
      error_message = "Error in get_character_activity: #{inspect(e)}"
      AppLogger.api_error(error_message)
      {:error, {:domain_error, :map, {:exception, error_message}}}
  end
end
