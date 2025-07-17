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

    # Wait for both tasks with extended timeout for startup
    # Increased to 60 seconds for startup robustness
    timeout = 60_000

    try do
      results = Task.await_many(tasks, timeout)
      process_results(results)
    rescue
      e ->
        AppLogger.api_error("Map initialization failed with exception",
          error: inspect(e),
          timeout: timeout
        )

        # Continue startup even if map data fails
        :ok
    catch
      :exit, reason ->
        AppLogger.api_error("Map initialization timed out",
          reason: inspect(reason),
          timeout: timeout
        )

        # Continue startup even if map data fails
        :ok
    end
  end

  defp process_results(results) do
    # Log results and update stats
    Enum.each(results, fn
      {:ok, type, count} ->
        AppLogger.api_info("Successfully fetched #{type}",
          count: count
        )

        # Update the stats tracking
        case type do
          "systems" -> WandererNotifier.Core.Stats.set_tracked_count(:systems, count)
          "characters" -> WandererNotifier.Core.Stats.set_tracked_count(:characters, count)
          _ -> :ok
        end

      {:error, type, reason} ->
        AppLogger.api_error("Failed to fetch #{type}",
          error: inspect(reason)
        )
    end)

    :ok
  end

  defp fetch_systems do
    AppLogger.api_info("Starting systems fetch")
    start_time = System.monotonic_time(:millisecond)

    case SystemsClient.fetch_and_cache_systems() do
      {:ok, systems} ->
        elapsed = System.monotonic_time(:millisecond) - start_time

        AppLogger.api_info("Systems fetch completed",
          count: length(systems),
          elapsed_ms: elapsed
        )

        {:ok, "systems", length(systems)}

      error ->
        elapsed = System.monotonic_time(:millisecond) - start_time

        AppLogger.api_error("Systems fetch failed",
          error: inspect(error),
          elapsed_ms: elapsed
        )

        {:error, "systems", error}
    end
  end

  defp fetch_characters do
    AppLogger.api_info("Starting characters fetch")
    start_time = System.monotonic_time(:millisecond)

    case CharactersClient.fetch_and_cache_characters() do
      {:ok, characters} ->
        elapsed = System.monotonic_time(:millisecond) - start_time

        AppLogger.api_info("Characters fetch completed",
          count: length(characters),
          elapsed_ms: elapsed
        )

        {:ok, "characters", length(characters)}

      error ->
        elapsed = System.monotonic_time(:millisecond) - start_time

        AppLogger.api_error("Characters fetch failed",
          error: inspect(error),
          elapsed_ms: elapsed
        )

        {:error, "characters", error}
    end
  end
end
