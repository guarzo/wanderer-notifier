defmodule WandererNotifier.Cache.Metrics do
  @moduledoc """
  Cache performance metrics collection and reporting.

  This module provides comprehensive metrics collection for cache operations,
  including hit/miss ratios, operation timing, memory usage, and eviction tracking.

  ## Features

  - Cache hit/miss ratio tracking
  - Operation timing measurements
  - Memory usage monitoring
  - Cache eviction and expiration tracking
  - Telemetry integration for real-time reporting
  - Configurable metrics collection intervals

  ## Usage

  ```elixir
  # Initialize metrics collection
  WandererNotifier.Cache.Metrics.init()

  # Record cache operation
  WandererNotifier.Cache.Metrics.record_hit(:character, 123456)
  WandererNotifier.Cache.Metrics.record_miss(:character, 123456)

  # Record operation timing
  WandererNotifier.Cache.Metrics.record_operation_time(:get, 15)

  # Get current metrics
  metrics = WandererNotifier.Cache.Metrics.get_metrics()
  ```
  """

  use GenServer
  require Logger

  @type metric_key :: atom()
  @type metric_value :: number()
  @type cache_domain ::
          :character | :corporation | :alliance | :system | :type | :killmail | :custom
  @type operation_type :: :get | :put | :delete | :clear

  # Default metrics collection interval in milliseconds
  @default_collection_interval 30_000
  # Maximum number of domains to track to prevent unbounded growth
  @max_domains 50
  # Maximum number of operation types to track
  @max_operations 20

  @doc """
  Starts the metrics collection GenServer.

  ## Options
  - `:collection_interval` - Interval in milliseconds for collecting metrics (default: 5000)
  - `:name` - Name for the GenServer (default: __MODULE__)
  """
  def start_link(opts \\ []) do
    {name, opts} = Keyword.pop(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Initializes metrics collection.

  This function should be called during application startup to ensure
  metrics collection is properly initialized.
  """
  @spec init() :: :ok
  def init do
    # Initialize telemetry events
    :telemetry.attach_many(
      "cache-metrics",
      [
        [:wanderer_notifier, :cache, :hit],
        [:wanderer_notifier, :cache, :miss],
        [:wanderer_notifier, :cache, :operation],
        [:wanderer_notifier, :cache, :eviction],
        [:wanderer_notifier, :cache, :expiration]
      ],
      &__MODULE__.handle_telemetry_event/4,
      %{}
    )

    Logger.info("Cache metrics collection initialized")
    :ok
  end

  @doc """
  Records a cache hit for a specific domain and ID.

  ## Parameters
  - domain: The cache domain (e.g., :character, :corporation)
  - id: The entity ID
  - metadata: Additional metadata (optional)
  """
  @spec record_hit(cache_domain(), term(), map()) :: :ok
  def record_hit(domain, id, metadata \\ %{}) do
    :telemetry.execute(
      [:wanderer_notifier, :cache, :hit],
      %{count: 1},
      %{domain: domain, id: id, metadata: metadata}
    )
  end

  @doc """
  Records a cache miss for a specific domain and ID.

  ## Parameters
  - domain: The cache domain (e.g., :character, :corporation)
  - id: The entity ID
  - metadata: Additional metadata (optional)
  """
  @spec record_miss(cache_domain(), term(), map()) :: :ok
  def record_miss(domain, id, metadata \\ %{}) do
    :telemetry.execute(
      [:wanderer_notifier, :cache, :miss],
      %{count: 1},
      %{domain: domain, id: id, metadata: metadata}
    )
  end

  @doc """
  Records cache operation timing.

  ## Parameters
  - operation: The type of operation (:get, :put, :delete, :clear)
  - duration_ms: Duration in milliseconds
  - metadata: Additional metadata (optional)
  """
  @spec record_operation_time(operation_type(), number(), map()) :: :ok
  def record_operation_time(operation, duration_ms, metadata \\ %{}) do
    :telemetry.execute(
      [:wanderer_notifier, :cache, :operation],
      %{duration: duration_ms},
      %{operation: operation, metadata: metadata}
    )
  end

  @doc """
  Records cache eviction event.

  ## Parameters
  - reason: Reason for eviction (e.g., :ttl_expired, :capacity_exceeded)
  - metadata: Additional metadata (optional)
  """
  @spec record_eviction(atom(), map()) :: :ok
  def record_eviction(reason, metadata \\ %{}) do
    :telemetry.execute(
      [:wanderer_notifier, :cache, :eviction],
      %{count: 1},
      %{reason: reason, metadata: metadata}
    )
  end

  @doc """
  Records cache expiration event.

  ## Parameters
  - domain: The cache domain
  - id: The entity ID
  - metadata: Additional metadata (optional)
  """
  @spec record_expiration(cache_domain(), term(), map()) :: :ok
  def record_expiration(domain, id, metadata \\ %{}) do
    :telemetry.execute(
      [:wanderer_notifier, :cache, :expiration],
      %{count: 1},
      %{domain: domain, id: id, metadata: metadata}
    )
  end

  @doc """
  Gets current cache metrics.

  ## Returns
  Map containing current metrics including:
  - hit_ratio: Cache hit ratio as a percentage
  - miss_ratio: Cache miss ratio as a percentage
  - total_operations: Total number of cache operations
  - average_operation_time: Average operation time in milliseconds
  - memory_usage: Current memory usage information
  - evictions: Number of cache evictions
  - expirations: Number of cache expirations
  """
  @spec get_metrics() :: map()
  def get_metrics do
    GenServer.call(__MODULE__, :get_metrics)
  end

  @doc """
  Gets detailed metrics for a specific domain.

  ## Parameters
  - domain: The cache domain to get metrics for

  ## Returns
  Map containing domain-specific metrics
  """
  @spec get_domain_metrics(cache_domain()) :: map()
  def get_domain_metrics(domain) do
    GenServer.call(__MODULE__, {:get_domain_metrics, domain})
  end

  @doc """
  Resets all metrics counters.

  ## Returns
  :ok
  """
  @spec reset_metrics() :: :ok
  def reset_metrics do
    GenServer.call(__MODULE__, :reset_metrics)
  end

  @doc """
  Gets cache hit ratio for a specific domain.

  ## Parameters
  - domain: The cache domain

  ## Returns
  Float representing the hit ratio (0.0 to 1.0)
  """
  @spec get_hit_ratio(cache_domain()) :: float()
  def get_hit_ratio(domain) do
    GenServer.call(__MODULE__, {:get_hit_ratio, domain})
  end

  # GenServer callbacks

  @impl GenServer
  def init(opts) do
    collection_interval = Keyword.get(opts, :collection_interval, @default_collection_interval)

    state = %{
      collection_interval: collection_interval,
      metrics: %{
        hits: %{},
        misses: %{},
        operations: %{},
        evictions: 0,
        expirations: 0,
        memory_usage: %{}
      },
      last_collection: System.monotonic_time(:millisecond),
      domain_count: 0,
      operation_count: 0
    }

    # Schedule periodic metrics collection
    Process.send_after(self(), :collect_metrics, collection_interval)

    {:ok, state}
  end

  @impl GenServer
  def handle_call(:get_metrics, _from, state) do
    metrics = calculate_aggregate_metrics(state.metrics)
    {:reply, metrics, state}
  end

  @impl GenServer
  def handle_call({:get_domain_metrics, domain}, _from, state) do
    metrics = calculate_domain_metrics(state.metrics, domain)
    {:reply, metrics, state}
  end

  @impl GenServer
  def handle_call(:reset_metrics, _from, state) do
    new_state = %{
      state
      | metrics: %{
          hits: %{},
          misses: %{},
          operations: %{},
          evictions: 0,
          expirations: 0,
          memory_usage: %{}
        },
        domain_count: 0,
        operation_count: 0
    }

    {:reply, :ok, new_state}
  end

  @impl GenServer
  def handle_call({:get_hit_ratio, domain}, _from, state) do
    ratio = calculate_hit_ratio(state.metrics, domain)
    {:reply, ratio, state}
  end

  @impl GenServer
  def handle_info(:collect_metrics, state) do
    # Collect memory usage and other system metrics
    memory_usage = collect_memory_usage()

    new_metrics = Map.put(state.metrics, :memory_usage, memory_usage)

    new_state = %{
      state
      | metrics: new_metrics,
        last_collection: System.monotonic_time(:millisecond)
    }

    # Schedule next collection
    Process.send_after(self(), :collect_metrics, state.collection_interval)

    {:noreply, new_state}
  end

  @doc false
  def handle_telemetry_event([:wanderer_notifier, :cache, :hit], measurements, metadata, _config) do
    GenServer.cast(__MODULE__, {:record_hit, measurements, metadata})
  end

  def handle_telemetry_event(
        [:wanderer_notifier, :cache, :miss],
        measurements,
        metadata,
        _config
      ) do
    GenServer.cast(__MODULE__, {:record_miss, measurements, metadata})
  end

  def handle_telemetry_event(
        [:wanderer_notifier, :cache, :operation],
        measurements,
        metadata,
        _config
      ) do
    GenServer.cast(__MODULE__, {:record_operation, measurements, metadata})
  end

  def handle_telemetry_event(
        [:wanderer_notifier, :cache, :eviction],
        measurements,
        metadata,
        _config
      ) do
    GenServer.cast(__MODULE__, {:record_eviction, measurements, metadata})
  end

  def handle_telemetry_event(
        [:wanderer_notifier, :cache, :expiration],
        measurements,
        metadata,
        _config
      ) do
    GenServer.cast(__MODULE__, {:record_expiration, measurements, metadata})
  end

  # Private functions

  @impl GenServer
  def handle_cast({:record_hit, measurements, metadata}, state) do
    domain = Map.get(metadata, :domain, :unknown)

    # Prevent unbounded domain growth
    if not Map.has_key?(state.metrics.hits, domain) and
         map_size(state.metrics.hits) >= @max_domains do
      # Don't track new domains if we've hit the limit
      {:noreply, state}
    else
      current_count = get_in(state.metrics, [:hits, domain]) || 0
      new_count = current_count + Map.get(measurements, :count, 1)

      new_metrics = put_in(state.metrics, [:hits, domain], new_count)

      new_domain_count =
        if Map.has_key?(state.metrics.hits, domain),
          do: state.domain_count,
          else: state.domain_count + 1

      {:noreply, %{state | metrics: new_metrics, domain_count: new_domain_count}}
    end
  end

  @impl GenServer
  def handle_cast({:record_miss, measurements, metadata}, state) do
    domain = Map.get(metadata, :domain, :unknown)

    # Prevent unbounded domain growth
    if not Map.has_key?(state.metrics.misses, domain) and
         map_size(state.metrics.misses) >= @max_domains do
      # Don't track new domains if we've hit the limit
      {:noreply, state}
    else
      current_count = get_in(state.metrics, [:misses, domain]) || 0
      new_count = current_count + Map.get(measurements, :count, 1)

      new_metrics = put_in(state.metrics, [:misses, domain], new_count)
      {:noreply, %{state | metrics: new_metrics}}
    end
  end

  @impl GenServer
  def handle_cast({:record_operation, measurements, metadata}, state) do
    operation = Map.get(metadata, :operation, :unknown)
    duration = Map.get(measurements, :duration, 0)

    # Prevent unbounded operation growth
    if not Map.has_key?(state.metrics.operations, operation) and
         map_size(state.metrics.operations) >= @max_operations do
      # Don't track new operations if we've hit the limit
      {:noreply, state}
    else
      {current_total, current_count} = get_in(state.metrics, [:operations, operation]) || {0, 0}
      new_total = current_total + duration
      new_count = current_count + 1

      new_metrics = put_in(state.metrics, [:operations, operation], {new_total, new_count})

      new_operation_count =
        if Map.has_key?(state.metrics.operations, operation),
          do: state.operation_count,
          else: state.operation_count + 1

      {:noreply, %{state | metrics: new_metrics, operation_count: new_operation_count}}
    end
  end

  @impl GenServer
  def handle_cast({:record_eviction, measurements, _metadata}, state) do
    current_count = state.metrics.evictions
    new_count = current_count + Map.get(measurements, :count, 1)

    new_metrics = Map.put(state.metrics, :evictions, new_count)
    {:noreply, %{state | metrics: new_metrics}}
  end

  @impl GenServer
  def handle_cast({:record_expiration, measurements, _metadata}, state) do
    current_count = state.metrics.expirations
    new_count = current_count + Map.get(measurements, :count, 1)

    new_metrics = Map.put(state.metrics, :expirations, new_count)
    {:noreply, %{state | metrics: new_metrics}}
  end

  defp calculate_aggregate_metrics(metrics) do
    total_hits = metrics.hits |> Map.values() |> Enum.sum()
    total_misses = metrics.misses |> Map.values() |> Enum.sum()
    total_operations = total_hits + total_misses

    hit_ratio = if total_operations > 0, do: total_hits / total_operations, else: 0.0
    miss_ratio = if total_operations > 0, do: total_misses / total_operations, else: 0.0

    average_operation_time = calculate_average_operation_time(metrics.operations)

    %{
      hit_ratio: hit_ratio,
      miss_ratio: miss_ratio,
      total_operations: total_operations,
      total_hits: total_hits,
      total_misses: total_misses,
      average_operation_time: average_operation_time,
      memory_usage: metrics.memory_usage,
      evictions: metrics.evictions,
      expirations: metrics.expirations,
      per_domain: calculate_per_domain_metrics(metrics)
    }
  end

  defp calculate_domain_metrics(metrics, domain) do
    hits = get_in(metrics, [:hits, domain]) || 0
    misses = get_in(metrics, [:misses, domain]) || 0
    total = hits + misses

    hit_ratio = if total > 0, do: hits / total, else: 0.0
    miss_ratio = if total > 0, do: misses / total, else: 0.0

    %{
      domain: domain,
      hits: hits,
      misses: misses,
      total_operations: total,
      hit_ratio: hit_ratio,
      miss_ratio: miss_ratio
    }
  end

  defp calculate_hit_ratio(metrics, domain) do
    hits = get_in(metrics, [:hits, domain]) || 0
    misses = get_in(metrics, [:misses, domain]) || 0
    total = hits + misses

    if total > 0, do: hits / total, else: 0.0
  end

  defp calculate_per_domain_metrics(metrics) do
    all_domains =
      Map.keys(metrics.hits)
      |> Enum.concat(Map.keys(metrics.misses))
      |> Enum.uniq()

    Enum.map(all_domains, fn domain ->
      {domain, calculate_domain_metrics(metrics, domain)}
    end)
    |> Map.new()
  end

  defp calculate_average_operation_time(operations) do
    if map_size(operations) > 0 do
      {total_time, total_count} =
        operations
        |> Map.values()
        |> Enum.reduce({0, 0}, fn {time, count}, {acc_time, acc_count} ->
          {acc_time + time, acc_count + count}
        end)

      if total_count > 0, do: total_time / total_count, else: 0.0
    else
      0.0
    end
  end

  defp collect_memory_usage do
    try do
      # Get cache memory usage from Cachex if available
      cache_name = WandererNotifier.Cache.Config.cache_name()

      case WandererNotifier.Cache.Adapter.adapter() do
        Cachex ->
          {:ok, stats} = Cachex.stats(cache_name)

          %{
            cache_stats: stats,
            memory_usage: Map.get(stats, :memory, 0)
          }

        _other ->
          # Fallback for other adapters
          %{
            cache_stats: %{},
            memory_usage: 0
          }
      end
    rescue
      _ ->
        %{
          cache_stats: %{},
          memory_usage: 0
        }
    end
  end
end
