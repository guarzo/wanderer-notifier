defmodule WandererNotifier.Api.Map.Client do
  @moduledoc """
  Client for interacting with the Wanderer map API.
  
  This module provides a simplified facade over the specific client modules
  for different map API endpoints, handling feature checks and error management.
  """
  require Logger
  alias WandererNotifier.Api.Map.SystemsClient
  alias WandererNotifier.Api.Map.CharactersClient
  # No need to alias UrlBuilder anymore, we've moved the logic to the dedicated module
  alias WandererNotifier.Core.Features
  alias WandererNotifier.Data.Cache.Repository, as: CacheRepo

  @doc """
  Updates system information from the map API.
  
  ## Returns
    - {:ok, systems} on success
    - {:error, reason} on failure
  """
  def update_systems do
    try do
      if Features.enabled?(:system_tracking) do
        SystemsClient.update_systems()
      else
        Logger.debug("[Map.Client] System tracking disabled due to license restrictions")
        {:error, :feature_disabled}
      end
    rescue
      e ->
        Logger.error("[Map.Client] Error in update_systems: #{inspect(e)}")
        Logger.error("[Map.Client] Stacktrace: #{inspect(Process.info(self(), :current_stacktrace))}")
        {:error, {:exception, e}}
    end
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
    try do
      if Features.enabled?(:system_tracking) do
        # Updated to work with new SystemsClient module that returns MapSystem structs
        case SystemsClient.update_systems(cached_systems) do
          {:ok, systems} -> {:ok, systems}
          error -> error
        end
      else
        Logger.debug("[Map.Client] System tracking disabled due to license restrictions")
        {:error, :feature_disabled}
      end
    rescue
      e ->
        Logger.error("[Map.Client] Error in update_systems_with_cache: #{inspect(e)}")
        Logger.error("[Map.Client] Stacktrace: #{inspect(Process.info(self(), :current_stacktrace))}")
        {:error, {:exception, e}}
    end
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
    try do
      if Features.enabled?(:tracked_characters_notifications) do
        Logger.debug(
          "[Map.Client] Character tracking is enabled, checking for tracked characters"
        )

        # Use provided cached_characters if available, otherwise get from cache
        current_characters = cached_characters || CacheRepo.get("map:characters") || []

        if Features.limit_reached?(:tracked_characters, length(current_characters)) do
          Logger.warning(
            "[Map.Client] Character tracking limit reached (#{length(current_characters)}). Upgrade license for more."
          )

          {:error, :limit_reached}
        else
          # Delegate to the CharactersClient for actual implementation
          # Updated to work with new CharactersClient module that returns Character structs
          case CharactersClient.update_tracked_characters(current_characters) do
            {:ok, characters} -> {:ok, characters}
            error -> error
          end
        end
      else
        Logger.debug(
          "[Map.Client] Character tracking disabled due to license restrictions or configuration"
        )

        {:error, :feature_disabled}
      end
    rescue
      e ->
        Logger.error("[Map.Client] Error in update_tracked_characters: #{inspect(e)}")
        Logger.error("[Map.Client] Stacktrace: #{inspect(Process.info(self(), :current_stacktrace))}")
        {:error, {:exception, e}}
    end
  end

  @doc """
  Retrieves character activity data from the map API.
  
  ## Parameters
    - slug: Optional map slug override
    
  ## Returns
    - {:ok, data} on success
    - {:error, reason} on failure
  """
  def get_character_activity(slug \\ nil) do
    try do
      if Features.enabled?(:activity_charts) do
        CharactersClient.get_character_activity(slug)
      else
        Logger.debug("[Map.Client] Activity charts disabled due to license restrictions")
        {:error, :feature_disabled}
      end
    rescue
      e ->
        error_message = "Error in get_character_activity: #{inspect(e)}"
        Logger.error(error_message)
        {:error, {:domain_error, :map, {:exception, error_message}}}
    end
  end
end