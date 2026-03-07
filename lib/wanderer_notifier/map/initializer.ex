defmodule WandererNotifier.Map.Initializer do
  @moduledoc """
  Handles initialization of map data (systems and characters) at startup.

  This module ensures that the cache is populated with initial data before
  the SSE connection starts receiving real-time updates.
  """

  require Logger

  alias WandererNotifier.Map.MapConfig
  alias WandererNotifier.Shared.Dependencies

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

    tracking = Dependencies.map_tracking_client()

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
    check_results_for_failures(results)
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

    {:ok, :processed}
  end

  # Strip any trailing "(slug)" suffix from labels emitted by execute_timed_fetch/2.
  # e.g. "systems(my-map)" -> "systems", "characters" -> "characters"
  defp base_label(label) when is_binary(label) do
    case String.split(label, "(", parts: 2) do
      [base, _] -> base
      [base] -> base
    end
  end

  defp check_results_for_failures(results) do
    results
    |> Enum.filter(&match?({:error, _, _}, &1))
    |> case do
      [] ->
        {:ok, :initialized}

      errors ->
        reasons = Enum.map(errors, fn {:error, label, reason} -> {label, reason} end)
        {:error, {:init_failures, reasons}}
    end
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
