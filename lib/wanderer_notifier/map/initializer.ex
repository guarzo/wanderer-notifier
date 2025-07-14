defmodule WandererNotifier.Map.Initializer do
  @moduledoc """
  Handles initialization of map data (systems and characters) at startup.
  
  This module ensures that the cache is populated with initial data before
  the SSE connection starts receiving real-time updates.
  """

  alias WandererNotifier.Logger.Logger, as: AppLogger
  alias WandererNotifier.Map.Clients.SystemsClient
  alias WandererNotifier.Map.Clients.CharactersClient

  @doc """
  Initializes map data by fetching systems and characters from the API.
  
  This function is called during application startup to ensure we have
  initial data before SSE starts.
  """
  @spec initialize_map_data() :: :ok
  def initialize_map_data do
    AppLogger.api_info("Initializing map data")
    
    # Fetch both systems and characters in parallel
    tasks = [
      Task.async(fn -> fetch_systems() end),
      Task.async(fn -> fetch_characters() end)
    ]
    
    # Wait for both tasks with a reasonable timeout
    results = Task.await_many(tasks, 30_000)
    
    # Log results
    Enum.each(results, fn
      {:ok, type, count} ->
        AppLogger.api_info("Successfully fetched #{type}",
          count: count
        )
        
      {:error, type, reason} ->
        AppLogger.api_error("Failed to fetch #{type}",
          error: inspect(reason)
        )
    end)
    
    :ok
  end

  defp fetch_systems do
    case SystemsClient.fetch_and_cache_systems() do
      {:ok, systems} ->
        {:ok, "systems", length(systems)}
        
      error ->
        {:error, "systems", error}
    end
  end

  defp fetch_characters do
    case CharactersClient.fetch_and_cache_characters() do
      {:ok, characters} ->
        {:ok, "characters", length(characters)}
        
      error ->
        {:error, "characters", error}
    end
  end
end