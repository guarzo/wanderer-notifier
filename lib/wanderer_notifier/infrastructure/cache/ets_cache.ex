defmodule WandererNotifier.Infrastructure.Cache.ETSCache do
  @moduledoc """
  **Unified, dependency-free ETS cache**

  - Replaces the old `ETSCache` **and** `SimpleETSCache`
  - Owns its ETS table through a lightweight GenServer
  - Supports TTL with millisecond precision
  - Implements `CacheBehaviour`
  """

  use GenServer
  @behaviour WandererNotifier.Infrastructure.Cache.CacheBehaviour

  # ---------------------------------------------------------------------------
  # Public API – starts a _named_ cache instance, defaults to :wanderer_cache
  # ---------------------------------------------------------------------------

  @default_table :wanderer_cache
  @cleanup_ms 30_000

  @doc "Start or obtain a cache process for the given table name"
  def start_link(opts \\ []) do
    table = Keyword.get(opts, :name, @default_table)
    GenServer.start_link(__MODULE__, table, name: via(table))
  end

  # ---------------------------------------------------------------------------
  # CacheBehaviour callbacks
  # ---------------------------------------------------------------------------

  @impl true
  def get(key, opts \\ []), do: call(:get, [key], opts)
  @impl true
  def set(key, val, ttl \\ nil, opts \\ []), do: call(:set, [key, val, ttl], opts)
  @impl true
  def put(key, val, opts \\ []), do: set(key, val, :infinity, opts)
  @impl true
  def delete(key, opts \\ []), do: call(:delete, [key], opts)
  @impl true
  def clear(opts \\ []), do: call(:clear, [], opts)

  @impl true
  def get_and_update(key, update_fun) do
    call(:get_and_update, [key, update_fun], [])
  end

  # Optional callbacks with default implementations
  @impl true
  def mget(keys), do: {:ok, Enum.map(keys, &get/1)}
  @impl true
  def get_kill(_kill_id), do: {:error, :not_implemented}
  @impl true
  def get_recent_kills, do: []
  @impl true
  def init_batch_logging, do: :ok

  # ---------------------------------------------------------------------------
  # GenServer implementation
  # ---------------------------------------------------------------------------

  @impl true
  def init(table) do
    :ets.new(table, [:named_table, :set, :public, read_concurrency: true])
    schedule_cleanup()
    {:ok, table}
  end

  @impl true
  def handle_call({:get, key}, _from, table) do
    reply =
      case :ets.lookup(table, key) do
        [{^key, val, exp}] ->
          if fresh?(exp) do
            {:ok, val}
          else
            :ets.delete(table, key)
            {:ok, nil}
          end

        _ ->
          {:ok, nil}
      end

    {:reply, reply, table}
  end

  @impl true
  def handle_call({:set, key, val, ttl}, _f, table) do
    :ets.insert(table, {key, val, expiry(ttl)})
    {:reply, {:ok, val}, table}
  end

  @impl true
  def handle_call({:delete, key}, _f, table) do
    :ets.delete(table, key)
    {:reply, :ok, table}
  end

  @impl true
  def handle_call(:clear, _f, table) do
    :ets.delete_all_objects(table)
    {:reply, :ok, table}
  end

  @impl true
  def handle_call({:get_and_update, key, update_fun}, _from, table) do
    current_val =
      case :ets.lookup(table, key) do
        [{^key, val, exp}] ->
          if fresh?(exp) do
            val
          else
            :ets.delete(table, key)
            nil
          end

        _ ->
          nil
      end

    {current_val, new_val} = update_fun.(current_val)

    if new_val != nil do
      :ets.insert(table, {key, new_val, expiry(nil)})
    end

    {:reply, {:ok, {current_val, new_val}}, table}
  end

  @impl true
  def handle_info(:cleanup, table) do
    for {k, _v, exp} <- :ets.tab2list(table), expired?(exp), do: :ets.delete(table, k)
    schedule_cleanup()
    {:noreply, table}
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp call(verb, args, opts) do
    table = Keyword.get(opts, :table, @default_table)

    [verb | args]
    |> List.to_tuple()
    |> (&GenServer.call(via(table), &1, 5_000)).()
  rescue
    ArgumentError -> {:error, :cache_not_started}
  end

  defp via(table), do: {:via, Registry, {WandererNotifier.Infrastructure.Cache.Registry, table}}

  defp expiry(nil), do: :infinity
  defp expiry(:infinity), do: :infinity
  defp expiry(ms) when ms > 0, do: System.monotonic_time(:millisecond) + ms
  defp expiry(_), do: :infinity

  defp fresh?(:infinity), do: true
  defp fresh?(ts), do: System.monotonic_time(:millisecond) < ts
  defp expired?(ts), do: not fresh?(ts)

  defp schedule_cleanup, do: Process.send_after(self(), :cleanup, @cleanup_ms)
end
