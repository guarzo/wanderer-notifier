defmodule WandererNotifier.Map.Reconciler do
  @moduledoc """
  Periodically reconciles the per-map system tracking state against upstream.

  ## Why this exists

  The MapRegistry reverse index (`system_id -> [map_slugs]`) is the single
  source of truth for killmail notification fan-out. It is maintained in two
  places:

    * Initial population at startup via `MapTrackingClient.fetch_and_cache_systems/2`
    * Delta maintenance via SSE `add_system` / `deleted_system` events

  If an SSE event is lost — e.g. a client dies silently during a long uptime
  (see commit cfe85c5c), a reconnect window drops an event, or the upstream
  misses a delete — the reverse index becomes permanently stale and the
  pipeline keeps fanning killmail notifications out to maps that no longer
  track the system. Users see "ghost" kill notifications for systems that
  were removed from their map, sometimes more than a day after removal.

  This reconciler closes that gap by re-fetching the authoritative system
  list from the map API every hour and pruning any reverse-index entries
  that are no longer present upstream. It is intentionally a safety net, not
  a replacement for SSE delta events — those remain the fast path.

  ## Safety properties

    * **First run is delayed.** The first reconcile is scheduled one full
      interval after start, so initialization via `Map.Initializer` is always
      fully effective before reconcile runs.
    * **Empty responses never clobber state.** If the upstream returns an
      empty list for any reason (transient bug, caching proxy returning stale
      200s, etc.) the reconcile is skipped for that map and existing state
      is preserved. A warning is logged.
    * **Errors never clobber state.** If the upstream returns an error
      (timeout, 5xx, connection refused) the reconcile is skipped for that
      map and existing state is preserved. A warning is logged.
    * **Per-map isolation.** Reconciles run under `Task.async_stream` with a
      concurrency cap; a failure on one map does not affect any other.
    * **Systems-only.** Character tracking is not reconciled — character
      rosters rarely change, and doing both in the same pass would double
      API traffic without a corresponding payoff.
  """

  use GenServer
  require Logger

  alias WandererNotifier.Domains.Tracking.Entities.System, as: SystemEntity
  alias WandererNotifier.Map.MapConfig
  alias WandererNotifier.Shared.Dependencies

  @reconcile_interval :timer.hours(1)
  @max_concurrency 5
  @task_timeout :timer.seconds(30)

  # ════════════════════════════════════════════════════════════════════════════
  # Public API
  # ════════════════════════════════════════════════════════════════════════════

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Reconciles the system reverse index for every currently registered map.

  Exposed publicly so operators can trigger a manual reconcile from IEx if
  they suspect staleness (`WandererNotifier.Map.Reconciler.reconcile_all/0`).

  Accepts the same `:registry` and `:fetch_fun` options as `reconcile_map/2`
  to make the full-tick path testable without touching application env.
  """
  @spec reconcile_all(keyword()) :: :ok
  def reconcile_all(opts \\ []) do
    registry = Keyword.get(opts, :registry, Dependencies.map_registry())
    fetch_fun = Keyword.get(opts, :fetch_fun, &default_fetch/1)

    maps = registry.all_maps()
    total = length(maps)
    start_ms = System.monotonic_time(:millisecond)

    summary =
      maps
      |> Task.async_stream(
        fn map_config -> safe_reconcile(map_config, registry, fetch_fun) end,
        max_concurrency: @max_concurrency,
        timeout: @task_timeout,
        on_timeout: :kill_task
      )
      |> Enum.reduce(empty_summary(), &aggregate_task_result/2)

    elapsed_ms = System.monotonic_time(:millisecond) - start_ms
    log_summary(summary, total, elapsed_ms)
    :ok
  end

  defp empty_summary do
    %{reconciled: 0, empty: 0, error: 0, crash: 0}
  end

  defp aggregate_task_result({:ok, {:ok, :reconciled}}, acc),
    do: %{acc | reconciled: acc.reconciled + 1}

  defp aggregate_task_result({:ok, {:ok, :skipped_empty}}, acc),
    do: %{acc | empty: acc.empty + 1}

  defp aggregate_task_result({:ok, {:error, _reason}}, acc),
    do: %{acc | error: acc.error + 1}

  defp aggregate_task_result({:exit, _reason}, acc),
    do: %{acc | crash: acc.crash + 1}

  defp log_summary(%{reconciled: rec, empty: emp, error: err, crash: crash}, total, elapsed_ms) do
    Logger.info(
      "Reconciler tick complete: #{rec}/#{total} reconciled, " <>
        "#{emp} empty (skipped), #{err} errors (skipped), #{crash} crashes",
      category: :reconcile,
      total: total,
      reconciled: rec,
      empty: emp,
      error: err,
      crash: crash,
      elapsed_ms: elapsed_ms
    )
  end

  @doc """
  Reconciles the system reverse index for a single map.

  ## Options

    * `:registry` - module implementing `MapRegistryBehaviour`. Defaults to
      `Dependencies.map_registry()`.
    * `:fetch_fun` - 1-arity function that takes a `MapConfig.t()` and
      returns `{:ok, [map()]}` or `{:error, term()}`. Defaults to a wrapper
      around `Dependencies.map_tracking_client().fetch_and_cache_systems/2`.

  ## Returns

    * `{:ok, :reconciled}` - fetch succeeded, diff was applied.
    * `{:ok, :skipped_empty}` - upstream returned an empty list; state
      intentionally left unchanged.
    * `{:error, reason}` - upstream fetch failed; state intentionally left
      unchanged.
  """
  @spec reconcile_map(MapConfig.t(), keyword()) ::
          {:ok, :reconciled | :skipped_empty} | {:error, term()}
  def reconcile_map(%MapConfig{} = map_config, opts \\ []) do
    registry = Keyword.get(opts, :registry, Dependencies.map_registry())
    fetch_fun = Keyword.get(opts, :fetch_fun, &default_fetch/1)

    case fetch_fun.(map_config) do
      {:ok, []} ->
        Logger.warning("Reconciler: empty system list, leaving state unchanged",
          map_slug: map_config.slug,
          category: :reconcile
        )

        {:ok, :skipped_empty}

      {:ok, fresh_systems} when is_list(fresh_systems) ->
        prune_stale_systems(map_config, registry, fresh_systems)
        {:ok, :reconciled}

      {:error, reason} ->
        Logger.warning("Reconciler: fetch failed, leaving state unchanged",
          map_slug: map_config.slug,
          reason: inspect(reason),
          category: :reconcile
        )

        {:error, reason}
    end
  end

  # ════════════════════════════════════════════════════════════════════════════
  # GenServer callbacks
  # ════════════════════════════════════════════════════════════════════════════

  @impl GenServer
  def init(_opts) do
    Logger.info("Map reconciler starting — first tick in #{interval_label()}",
      interval_ms: @reconcile_interval,
      category: :startup
    )

    {:ok, %{timer: schedule_reconcile()}}
  end

  @impl GenServer
  def handle_info(:reconcile, state) do
    do_reconcile()
    {:noreply, %{state | timer: schedule_reconcile()}}
  end

  # Catch-all for unexpected messages (mirrors SSEClient pattern from cfe85c5c)
  @impl GenServer
  def handle_info(msg, state) do
    Logger.warning("Map reconciler received unhandled message",
      message: inspect(msg, limit: 200)
    )

    {:noreply, state}
  end

  # ════════════════════════════════════════════════════════════════════════════
  # Private
  # ════════════════════════════════════════════════════════════════════════════

  defp do_reconcile do
    reconcile_all()
  rescue
    e ->
      Logger.error("Map reconciler tick crashed — state preserved",
        reason: Exception.message(e),
        stacktrace: Exception.format_stacktrace(__STACKTRACE__)
      )
  end

  defp safe_reconcile(map_config, registry, fetch_fun) do
    reconcile_map(map_config, registry: registry, fetch_fun: fetch_fun)
  rescue
    e ->
      Logger.error("Reconciler: exception while reconciling map",
        map_slug: map_config.slug,
        reason: Exception.message(e),
        category: :reconcile
      )

      {:error, {:exception, Exception.message(e)}}
  end

  defp prune_stale_systems(%MapConfig{slug: slug}, registry, fresh_systems) do
    fresh_ids = build_fresh_id_set(fresh_systems)
    current_ids = slug |> registry.systems_for_map() |> MapSet.new()
    stale_ids = MapSet.difference(current_ids, fresh_ids)
    stale_count = MapSet.size(stale_ids)

    if stale_count > 0 do
      Logger.info("Reconciler: pruning stale systems from reverse index",
        map_slug: slug,
        stale_count: stale_count,
        current_count: MapSet.size(current_ids),
        fresh_count: MapSet.size(fresh_ids),
        category: :reconcile
      )
    end

    Enum.each(stale_ids, fn stale_id ->
      registry.deindex_system(slug, stale_id)
    end)
  end

  # Builds a MapSet of normalized system_id strings. Entries whose id cannot
  # be normalized to an integer are silently dropped — they cannot match the
  # reverse index anyway and including them would poison the diff.
  defp build_fresh_id_set(fresh_systems) do
    fresh_systems
    |> Enum.reduce(MapSet.new(), fn system, acc ->
      case normalize_fresh_system_id(system) do
        nil -> acc
        id -> MapSet.put(acc, id)
      end
    end)
  end

  defp normalize_fresh_system_id(system) when is_map(system) do
    raw =
      system["solar_system_id"] || system[:solar_system_id] ||
        system["id"] || system[:id]

    case SystemEntity.normalize_solar_system_id(raw) do
      nil -> nil
      int_id -> Integer.to_string(int_id)
    end
  end

  defp normalize_fresh_system_id(_), do: nil

  defp default_fetch(%MapConfig{} = map_config) do
    Dependencies.map_tracking_client().fetch_and_cache_systems(map_config, true)
  end

  defp schedule_reconcile do
    Process.send_after(self(), :reconcile, @reconcile_interval)
  end

  defp interval_label do
    minutes = div(@reconcile_interval, 60_000)
    "#{minutes} minute(s)"
  end
end
