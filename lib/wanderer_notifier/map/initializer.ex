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
      e in HTTPoison.Error ->
        # Network/HTTP errors
        AppLogger.api_error("Map initialization network error",
          error: Exception.message(e),
          timeout: timeout
        )

        # Continue startup even if map data fails
        :ok

      e ->
        # Other unexpected errors
        AppLogger.api_error("Map initialization unexpected error",
          error: inspect(e),
          exception_type: e.__struct__,
          timeout: timeout
        )

        # Continue startup even if map data fails
        :ok
    catch
      :exit, {:timeout, _} ->
        # Specific timeout handling
        AppLogger.api_error("Map initialization timed out after #{timeout}ms",
          timeout: timeout
        )

        # Continue startup even if map data fails
        :ok

      :exit, reason ->
        # Other exit reasons
        AppLogger.api_error("Map initialization process exited",
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
    execute_timed_fetch(fn -> SystemsClient.fetch_and_cache_systems() end, "systems")
  end

  defp fetch_characters do
    execute_timed_fetch(fn -> CharactersClient.fetch_and_cache_characters() end, "characters")
  end

  defp execute_timed_fetch(fetch_function, label) do
    AppLogger.api_info("Starting #{label} fetch")
    start_time = System.monotonic_time(:millisecond)

    case fetch_function.() do
      {:ok, items} ->
        elapsed = System.monotonic_time(:millisecond) - start_time

        AppLogger.api_info("#{String.capitalize(label)} fetch completed",
          count: length(items),
          elapsed_ms: elapsed
        )

        {:ok, label, length(items)}

      error ->
        elapsed = System.monotonic_time(:millisecond) - start_time

        AppLogger.api_error("#{String.capitalize(label)} fetch failed",
          error: inspect(error),
          elapsed_ms: elapsed
        )

        {:error, label, error}
    end
  end
end
