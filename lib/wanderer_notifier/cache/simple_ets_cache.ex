defmodule WandererNotifier.Cache.SimpleETSCache do
  @moduledoc """
  Simple ETS-based cache implementation for testing.
  Uses a single table name from application config.
  
  ⚠️ WARNING: This cache implementation is intended for TEST ENVIRONMENTS ONLY.
  It has potential race conditions in get_and_update operations and lacks the
  robustness required for production use. Use Cachex or another production-ready
  cache implementation for production environments.
  """
  use GenServer

  @behaviour WandererNotifier.Cache.CacheBehaviour

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, :wanderer_test_cache)
    GenServer.start_link(__MODULE__, name, name: :"#{name}_server")
  end

  @impl GenServer
  def init(table_name) do
    # Create the ETS table owned by this process
    :ets.new(table_name, [:set, :public, :named_table, read_concurrency: true])
    {:ok, %{table_name: table_name}}
  end

  # CacheBehaviour implementation

  @impl true
  def get(key, _opts \\ []) do
    table = get_table_name()

    case :ets.lookup(table, key) do
      [{^key, value, expiry}] ->
        if expired?(expiry) do
          :ets.delete(table, key)
          {:ok, nil}
        else
          {:ok, value}
        end

      [] ->
        {:ok, nil}
    end
  rescue
    _ -> {:error, :table_not_found}
  end

  @impl true
  def set(key, value, ttl) do
    table = get_table_name()
    expiry = calculate_expiry(ttl)

    :ets.insert(table, {key, value, expiry})
    {:ok, value}
  rescue
    _ -> {:error, :table_not_found}
  end

  @impl true
  def put(key, value) do
    set(key, value, :infinity)
  end

  @impl true
  def delete(key) do
    table = get_table_name()
    :ets.delete(table, key)
    :ok
  rescue
    _ -> {:error, :table_not_found}
  end

  @impl true
  def clear() do
    table = get_table_name()
    :ets.delete_all_objects(table)
    :ok
  rescue
    _ -> {:error, :table_not_found}
  end

  @impl true
  def get_and_update(key, update_fun) do
    case get(key) do
      {:ok, current_value} ->
        handle_update_result(key, update_fun.(current_value), current_value)

      error ->
        error
    end
  end

  defp handle_update_result(key, update_result, current_value) do
    case update_result do
      {get_value, new_value} ->
        update_cache_value(key, new_value)
        {:ok, {get_value, new_value}}

      :pop ->
        delete(key)
        {:ok, {current_value, nil}}

      other ->
        {:error, {:invalid_return, other}}
    end
  end

  defp update_cache_value(key, :pop), do: delete(key)
  defp update_cache_value(key, new_value), do: put(key, new_value)

  @impl true
  def mget(keys) when is_list(keys) do
    results =
      Enum.map(keys, fn key ->
        case get(key) do
          {:ok, value} -> {:ok, value}
          error -> error
        end
      end)

    {:ok, results}
  end

  @impl true
  def get_recent_kills() do
    []
  end

  @impl true
  def get_kill(kill_id) do
    case get("kill:#{kill_id}") do
      {:ok, nil} -> {:error, :not_cached}
      {:ok, kill} -> {:ok, kill}
      error -> error
    end
  end

  @impl true
  def init_batch_logging() do
    :ok
  end

  # GenServer callbacks

  @impl GenServer
  def handle_call(_, _from, state) do
    {:reply, :ok, state}
  end

  @impl GenServer
  def handle_cast(_, state) do
    {:noreply, state}
  end

  @impl GenServer
  def handle_info(_, state) do
    {:noreply, state}
  end

  # Private helpers

  defp get_table_name() do
    Application.get_env(:wanderer_notifier, :cache_name, :wanderer_test_cache)
  end

  defp calculate_expiry(:infinity), do: :infinity

  defp calculate_expiry(ttl) when is_integer(ttl) do
    System.os_time(:second) + ttl
  end

  defp expired?(:infinity), do: false

  defp expired?(expiry) when is_integer(expiry) do
    System.os_time(:second) > expiry
  end

  defp expired?(_), do: true
end
