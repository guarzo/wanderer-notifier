defmodule WandererNotifier.Map.Clients.Client do
  @moduledoc """
  Client for interacting with the EVE Online Map API.

  This module provides a simplified facade over the specific client modules
  for different map API endpoints, handling feature checks and error management.
  """

  alias WandererNotifier.Logger.Logger
  alias WandererNotifier.Map.Clients.{SystemsClient, CharactersClient}

  @doc """
  Updates system information from the map API.

  ## Returns
    - {:ok, systems} on success
    - {:error, reason} on failure
  """
  def update_systems do
    case SystemsClient.update_data([]) do
      {:ok, systems} ->
        {:ok, systems}

      {:error, reason} = error ->
        Logger.api_error("Failed to update systems", error: inspect(reason))
        error
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
    case SystemsClient.update_data(cached_systems) do
      {:ok, systems} ->
        {:ok, systems}

      {:error, reason} = error ->
        Logger.api_error("Failed to update systems with cache", error: inspect(reason))
        error
    end
  end

  @doc """
  Updates tracked character information from the map API.

  ## Parameters
    - cached_characters: Optional list of cached characters for comparison
    - opts: Options to pass to CharactersClient.update_tracked_characters

  ## Returns
    - {:ok, characters} on success
    - {:error, reason} on failure
  """
  def update_tracked_characters(cached_characters \\ [], opts \\ []) do
    case CharactersClient.update_data(cached_characters, opts) do
      {:ok, characters} ->
        {:ok, characters}

      {:error, reason} = error ->
        Logger.api_error("Failed to update tracked characters", error: inspect(reason))
        error
    end
  end
end
