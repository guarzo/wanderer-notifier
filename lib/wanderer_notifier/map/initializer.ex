defmodule WandererNotifier.Map.Initializer do
  @moduledoc """
  Handles initialization of map data (systems and characters) at startup.

  This module ensures that the cache is populated with initial data before
  the SSE connection starts receiving real-time updates.
  """

  require Logger

  @doc """
  Initializes map data by fetching systems and characters from the API.

  This function is called during application startup to ensure we have
  initial data before SSE starts. Uses sequential loading to prevent
  memory spikes from parallel bulk API calls.
  """
  @spec initialize_map_data() :: :ok
  def initialize_map_data do
    Logger.info("Initializing map data (sequential loading for memory efficiency)",
      category: :api
    )

    # Fetch sequentially to prevent memory spikes from parallel bulk operations
    try do
      # First fetch systems
      systems_result = fetch_systems()

      # Add delay between bulk operations to allow GC
      Process.sleep(1000)

      # Then fetch characters
      characters_result = fetch_characters()

      # Process results
      results = [systems_result, characters_result]
      process_results(results)
    rescue
      e in HTTPoison.Error ->
        # Network/HTTP errors
        Logger.error("Map initialization network error",
          error: Exception.message(e),
          category: :api
        )

        # Continue startup even if map data fails
        :ok

      e ->
        # Other unexpected errors
        Logger.error("Map initialization unexpected error",
          error: inspect(e),
          exception_type: e.__struct__,
          category: :api
        )

        # Continue startup even if map data fails
        :ok
    catch
      :exit, reason ->
        # Exit handling
        Logger.error("Map initialization process exited", reason: inspect(reason), category: :api)

        # Continue startup even if map data fails
        :ok
    end
  end

  defp process_results(results) do
    # Log results and update stats
    Enum.each(results, fn
      {:ok, type, count} ->
        Logger.info("Successfully fetched #{type}", count: count, category: :api)

        # Update the stats tracking
        case type do
          "systems" ->
            WandererNotifier.Shared.Metrics.set_tracked_count(
              :systems,
              count
            )

          "characters" ->
            WandererNotifier.Shared.Metrics.set_tracked_count(
              :characters,
              count
            )

          _ ->
            :ok
        end

      {:error, type, reason} ->
        Logger.error("Failed to fetch #{type}", error: inspect(reason), category: :api)
    end)

    :ok
  end

  defp fetch_systems do
    execute_timed_fetch(
      fn ->
        WandererNotifier.Domains.Tracking.MapTrackingClient.fetch_and_cache_systems(true)
      end,
      "systems"
    )
  end

  defp fetch_characters do
    execute_timed_fetch(
      fn ->
        WandererNotifier.Domains.Tracking.MapTrackingClient.fetch_and_cache_characters(true)
      end,
      "characters"
    )
  end

  # Dialyzer warns this pattern is unreachable in test environment
  @dialyzer {:nowarn_function, execute_timed_fetch: 2}
  defp execute_timed_fetch(fetch_function, label) do
    Logger.debug("Starting #{label} fetch", category: :api)
    start_time = System.monotonic_time(:millisecond)

    case fetch_function.() do
      {:ok, items} ->
        elapsed = System.monotonic_time(:millisecond) - start_time

        Logger.debug("#{String.capitalize(label)} fetch completed",
          count: length(items),
          elapsed_ms: elapsed,
          category: :api
        )

        {:ok, label, length(items)}

      error ->
        elapsed = System.monotonic_time(:millisecond) - start_time

        Logger.error("#{String.capitalize(label)} fetch failed",
          error: inspect(error),
          elapsed_ms: elapsed,
          category: :api
        )

        {:error, label, error}
    end
  end
end
