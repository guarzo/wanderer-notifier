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
  misses a delete — the reverse index becomes permanently out of sync. Two
  failure modes follow:

    * Lost `deleted_system` event → reverse index keeps a ghost entry; the
      pipeline keeps fanning killmail notifications out to a map that no
      longer tracks the system.
    * Lost `add_system` event → reverse index is missing a real entry; the
      WebSocket subscription never includes the new system, and killmails
      for it are silently dropped until process restart.

  This reconciler closes both gaps by re-fetching the authoritative system
  list from the map API every 15 minutes and reconciling the reverse index
  in BOTH directions: deindexing entries upstream no longer reports AND
  indexing entries upstream reports that the local index is missing. It is
  intentionally a safety net, not a replacement for SSE delta events —
  those remain the fast path.

  ## Safety properties

    * **First run is delayed.** The first reconcile is scheduled one full
      interval after start, so initialization via `Map.Initializer` is always
      fully effective before reconcile runs.
    * **Empty responses never clobber state.** If the upstream returns an
      empty list for any reason (transient bug, caching proxy returning stale
      200s, etc.) the reconcile is skipped for that map and existing state
      is preserved. A warning is logged.
    * **Malformed responses never clobber state.** If upstream returns a
      non-empty list whose entries all fail id normalization, the reconcile
      is skipped and existing state is preserved.
    * **Errors never clobber state.** If the upstream returns an error
      (timeout, 5xx, connection refused) the reconcile is skipped for that
      map and existing state is preserved. A warning is logged.
    * **Two-way repair.** When the upstream response is valid, the reverse
      index is reconciled in both directions: stale entries are deindexed
      AND missing entries are indexed. A one-way reconciler can only repair
      lost-delete events; lost-add events would persist until restart.
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

  @reconcile_interval :timer.minutes(15)
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
    %{reconciled: 0, empty: 0, malformed: 0, error: 0, crash: 0}
  end

  defp aggregate_task_result({:ok, {:ok, :reconciled}}, acc),
    do: %{acc | reconciled: acc.reconciled + 1}

  defp aggregate_task_result({:ok, {:ok, :skipped_empty}}, acc),
    do: %{acc | empty: acc.empty + 1}

  defp aggregate_task_result({:ok, {:ok, :skipped_malformed}}, acc),
    do: %{acc | malformed: acc.malformed + 1}

  defp aggregate_task_result({:ok, {:error, _reason}}, acc),
    do: %{acc | error: acc.error + 1}

  defp aggregate_task_result({:exit, _reason}, acc),
    do: %{acc | crash: acc.crash + 1}

  defp log_summary(summary, total, elapsed_ms) do
    %{reconciled: rec, empty: emp, malformed: mal, error: err, crash: crash} = summary

    Logger.info(
      "Reconciler tick complete: #{rec}/#{total} reconciled, " <>
        "#{emp} empty (skipped), #{mal} malformed (skipped), " <>
        "#{err} errors (skipped), #{crash} crashes",
      category: :reconcile,
      total: total,
      reconciled: rec,
      empty: emp,
      malformed: mal,
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
    * `{:ok, :skipped_malformed}` - upstream returned a non-empty list whose
      entries all failed id normalization; state intentionally left unchanged.
    * `{:error, reason}` - upstream fetch failed; state intentionally left
      unchanged.
  """
  @spec reconcile_map(MapConfig.t(), keyword()) ::
          {:ok, :reconciled | :skipped_empty | :skipped_malformed} | {:error, term()}
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
        handle_fresh_systems(map_config, registry, fresh_systems)

      {:error, reason} ->
        Logger.warning("Reconciler: fetch failed, leaving state unchanged",
          map_slug: map_config.slug,
          reason: inspect(reason),
          category: :reconcile
        )

        {:error, reason}
    end
  end

  # Computes the fresh id set once and gates on whether it yielded anything
  # useful. A non-empty upstream list whose entries all fail normalization
  # (e.g. a schema change, a proxy serving corrupted JSON) would otherwise
  # be treated as "the map tracks nothing" and wipe the entire reverse
  # index — exactly the clobber scenario the reconciler must not cause.
  defp handle_fresh_systems(map_config, registry, fresh_systems) do
    fresh_id_set = build_fresh_id_set(fresh_systems)

    if MapSet.size(fresh_id_set) == 0 do
      Logger.warning(
        "Reconciler: upstream returned list with no parseable system ids — " <>
          "treating as malformed, leaving state unchanged",
        map_slug: map_config.slug,
        upstream_count: length(fresh_systems),
        category: :reconcile
      )

      {:ok, :skipped_malformed}
    else
      reconcile_systems(map_config, registry, fresh_id_set)
      {:ok, :reconciled}
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

  # Two-way reconciliation: deindex entries upstream no longer reports, AND
  # index entries upstream reports that we're missing locally. Without the
  # second direction, a single missed SSE `add_system` event (e.g. dropped
  # during a reconnect window) leaves the reverse index permanently short
  # the new system, the WebSocket subscription never includes it, and
  # killmails for that system are silently dropped until process restart.
  # The reconciler is the ONLY safety net that runs post-startup, so it
  # MUST repair gaps in both directions.
  defp reconcile_systems(%MapConfig{slug: slug}, registry, fresh_id_set) do
    current_ids = slug |> registry.systems_for_map() |> MapSet.new()
    stale_ids = MapSet.difference(current_ids, fresh_id_set)
    missing_ids = MapSet.difference(fresh_id_set, current_ids)
    stale_count = MapSet.size(stale_ids)
    missing_count = MapSet.size(missing_ids)

    if stale_count > 0 or missing_count > 0 do
      Logger.info("Reconciler: repairing reverse index drift",
        map_slug: slug,
        stale_count: stale_count,
        missing_count: missing_count,
        current_count: MapSet.size(current_ids),
        fresh_count: MapSet.size(fresh_id_set),
        category: :reconcile
      )
    end

    Enum.each(stale_ids, &deindex_one_safe(registry, slug, &1))
    Enum.each(missing_ids, &index_one_safe(registry, slug, &1))
  end

  # Defensive deindex wrapper. The real MapRegistry.deindex_system/2 always
  # returns `:ok`, but a mock or alternate implementation could surface an
  # error or raise. We log and continue rather than short-circuit, because
  # aborting mid-loop would leave partial state worse than the best-effort
  # end state (stale ids after the failure point would remain stale *and*
  # we'd lose the signal that some ids were successfully pruned).
  defp deindex_one_safe(registry, slug, system_id) do
    case registry.deindex_system(slug, system_id) do
      :ok -> :ok
      {:ok, _} -> :ok
      {:error, reason} -> log_deindex_failure(slug, system_id, reason)
    end
  rescue
    e -> log_deindex_failure(slug, system_id, Exception.message(e))
  end

  defp log_deindex_failure(slug, system_id, reason) do
    Logger.warning(
      "Reconciler: failed to deindex stale system — continuing with remaining ids",
      map_slug: slug,
      system_id: system_id,
      reason: inspect(reason),
      category: :reconcile
    )
  end

  # Symmetric to deindex_one_safe — used when the reconciler discovers a
  # system that upstream tracks but the local reverse index is missing.
  defp index_one_safe(registry, slug, system_id) do
    case registry.index_system(slug, system_id) do
      :ok -> :ok
      {:ok, _} -> :ok
      {:error, reason} -> log_index_failure(slug, system_id, reason)
    end
  rescue
    e -> log_index_failure(slug, system_id, Exception.message(e))
  end

  defp log_index_failure(slug, system_id, reason) do
    Logger.warning(
      "Reconciler: failed to index missing system — continuing with remaining ids",
      map_slug: slug,
      system_id: system_id,
      reason: inspect(reason),
      category: :reconcile
    )
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

  # Normalizes each candidate independently so an unparseable-but-truthy
  # value (e.g. `"solar_system_id" => ""`) does not short-circuit a valid
  # fallback via Elixir's `||` operator. Same fix pattern as
  # SystemHandler.extract_solar_system_id/1.
  defp normalize_fresh_system_id(system) when is_map(system) do
    [
      Map.get(system, "solar_system_id"),
      Map.get(system, :solar_system_id),
      Map.get(system, "id"),
      Map.get(system, :id)
    ]
    |> Enum.find_value(&SystemEntity.normalize_solar_system_id/1)
    |> case do
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
