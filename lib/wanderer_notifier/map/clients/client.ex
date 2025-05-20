defmodule WandererNotifier.Map.Clients.Client do
  @moduledoc """
  Client for interacting with the Wanderer map API.

  This module provides a simplified facade over the specific client modules
  for different map API endpoints, handling feature checks and error management.
  """

  alias WandererNotifier.Map.Clients.SystemsClient
  alias WandererNotifier.Map.Clients.CharactersClient
  alias WandererNotifier.Cache.CachexImpl, as: CacheRepo
  alias WandererNotifier.Logger.Logger, as: AppLogger
  alias WandererNotifier.Cache.Keys

  @doc """
  Updates system information from the map API.

  ## Returns
    - {:ok, systems} on success
    - {:error, reason} on failure
  """
  def update_systems do
    if WandererNotifier.Config.system_tracking_enabled?() do
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
    if WandererNotifier.Config.system_tracking_enabled?() do
      # Updated to work with new SystemsClient module that returns {:ok, new_systems, all_systems}
      case SystemsClient.update_systems(cached_systems) do
        {:ok, _new_systems, all_systems} -> {:ok, all_systems}
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
    - opts: Options to pass to CharactersClient.update_tracked_characters

  ## Returns
    - {:ok, characters} on success
    - {:error, reason} on failure
  """
  def update_tracked_characters(cached_characters \\ nil, opts \\ []) do
    AppLogger.api_debug("Starting character update")

    cached_characters
    |> get_current_characters()
    |> ensure_list()
    |> CharactersClient.update_tracked_characters(opts)
  end

  # Helper function to get current characters from cache
  defp get_current_characters(nil), do: CacheRepo.get(Keys.character_list()) || []
  defp get_current_characters(chars), do: chars

  # Helper function to ensure we're working with a list
  defp ensure_list(nil), do: []
  defp ensure_list(list) when is_list(list), do: list
  defp ensure_list({:ok, list}) when is_list(list), do: list
  defp ensure_list(_), do: []
end
