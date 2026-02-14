defmodule WandererNotifier.Map.Initializer do
  @moduledoc """
  Handles initialization of map data (systems and characters) at startup.

  This module ensures that the cache is populated with initial data before
  the SSE connection starts receiving real-time updates.
  """

  require Logger

  alias WandererNotifier.Map.MapConfig

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

      # Then fetch characters
      characters_result = fetch_characters()

      # Process results
      results = [systems_result, characters_result]
      process_results(results)
    rescue
      e in [MatchError, CaseClauseError] ->
        # Handle pattern matching errors from fetch operations
        Logger.error(
          "Map initialization network error: #{WandererNotifier.Shared.Utils.ErrorHandler.format_error(e)}"
        )

        # Continue startup even if map data fails
        :ok

      e ->
        # Other unexpected errors - conditional debug info based on environment
        if WandererNotifier.Shared.Config.production?() do
          Logger.error(
            "Map initialization unexpected error: #{WandererNotifier.Shared.Utils.ErrorHandler.format_error(e)}"
          )
        else
          Logger.error(
            "Map initialization unexpected error: #{WandererNotifier.Shared.Utils.ErrorHandler.format_error(e)} (#{e.__struct__}). Exception: #{Exception.message(e)}. Stacktrace: #{Exception.format_stacktrace(__STACKTRACE__)}"
          )
        end

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

  @doc """
  Initializes map data for a specific map configuration.

  Used in multi-map mode to initialize data for each map independently.
  Fetches systems and characters using scoped cache keys.
  """
  @spec initialize_map_data_for(MapConfig.t()) :: {:ok, :initialized} | {:error, term()}
  def initialize_map_data_for(%MapConfig{} = map_config) do
    Logger.info("Initializing map data for #{map_config.slug}",
      map_slug: map_config.slug,
      category: :api
    )

    tracking = WandererNotifier.Domains.Tracking.MapTrackingClient

    systems_result =
      execute_timed_fetch(
        fn -> tracking.fetch_and_cache_systems(map_config, true) end,
        "systems(#{map_config.slug})"
      )

    characters_result =
      execute_timed_fetch(
        fn -> tracking.fetch_and_cache_characters(map_config, true) end,
        "characters(#{map_config.slug})"
      )

    results = [systems_result, characters_result]
    process_results(results)

    errors =
      Enum.filter(results, fn
        {:error, _, _} -> true
        _ -> false
      end)

    if errors == [] do
      {:ok, :initialized}
    else
      reasons = Enum.map(errors, fn {:error, label, reason} -> {label, reason} end)
      {:error, {:init_failures, reasons}}
    end
  rescue
    e ->
      stacktrace = __STACKTRACE__

      Logger.error("Map initialization failed for #{map_config.slug}",
        error: Exception.message(e),
        exception: e,
        stacktrace: Exception.format(:error, e, stacktrace),
        category: :api
      )

      {:error, {:exception, Exception.message(e)}}
  end

  defp process_results(results) do
    # Log results and update stats
    Enum.each(results, fn
      {:ok, type, count} ->
        Logger.info("Successfully fetched #{type}", count: count, category: :api)

        # Update the stats tracking (normalize label to strip any "(slug)" suffix)
        case base_label(type) do
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

  # Strip any trailing "(slug)" suffix from labels emitted by execute_timed_fetch/2.
  # e.g. "systems(my-map)" -> "systems", "characters" -> "characters"
  defp base_label(label) when is_binary(label) do
    case String.split(label, "(", parts: 2) do
      [base, _] -> base
      [base] -> base
    end
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
