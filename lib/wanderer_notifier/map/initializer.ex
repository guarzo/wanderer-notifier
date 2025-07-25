defmodule WandererNotifier.Map.Initializer do
  @moduledoc """
  Handles initialization of map data (systems and characters) at startup.

  This module ensures that the cache is populated with initial data before
  the SSE connection starts receiving real-time updates.
  """

  alias WandererNotifier.Shared.Logger.Logger, as: AppLogger

  @doc """
  Initializes map data by fetching systems and characters from the API.

  This function is called during application startup to ensure we have
  initial data before SSE starts. Uses sequential loading to prevent
  memory spikes from parallel bulk API calls.
  """
  @spec initialize_map_data() :: :ok
  def initialize_map_data do
    AppLogger.api_info("Initializing map data (sequential loading for memory efficiency)")

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
        AppLogger.api_error("Map initialization network error",
          error: Exception.message(e)
        )

        # Continue startup even if map data fails
        :ok

      e ->
        # Other unexpected errors
        AppLogger.api_error("Map initialization unexpected error",
          error: inspect(e),
          exception_type: e.__struct__
        )

        # Continue startup even if map data fails
        :ok
    catch
      :exit, reason ->
        # Exit handling
        AppLogger.api_error("Map initialization process exited",
          reason: inspect(reason)
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
          "systems" ->
            WandererNotifier.Application.Services.Stats.set_tracked_count(:systems, count)

          "characters" ->
            WandererNotifier.Application.Services.Stats.set_tracked_count(:characters, count)

          _ ->
            :ok
        end

      {:error, type, reason} ->
        AppLogger.api_error("Failed to fetch #{type}",
          error: inspect(reason)
        )
    end)

    :ok
  end

  defp fetch_systems do
    execute_timed_fetch(
      fn -> WandererNotifier.Domains.Tracking.Clients.UnifiedClient.fetch_and_cache_systems() end,
      "systems"
    )
  end

  defp fetch_characters do
    execute_timed_fetch(
      fn ->
        WandererNotifier.Domains.Tracking.Clients.UnifiedClient.fetch_and_cache_characters()
      end,
      "characters"
    )
  end

  # Dialyzer warns this pattern is unreachable in test environment
  @dialyzer {:nowarn_function, execute_timed_fetch: 2}
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
