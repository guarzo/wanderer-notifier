defmodule WandererNotifier.Cache.ETSCache do
  @moduledoc """
  Lightweight ETS-based cache implementation for testing.

  This provides a pure Elixir cache without external dependencies,
  making tests faster and more reliable.
  """
  use GenServer

  @behaviour WandererNotifier.Cache.CacheBehaviour

  @table_name :wanderer_test_cache_ets

  # Store the table name in the process state
  defmodule State do
    @moduledoc """
    State struct for the ETSCache GenServer.

    Holds the ETS table name for the cache instance.
    """
    defstruct [:table_name]
  end

  @doc """
  Child spec for supervisor.
  """
  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      type: :worker,
      restart: :permanent,
      shutdown: 500
    }
  end

  @doc """
  Starts the ETS cache.
  """
  def start_link(opts \\ []) do
    table_name = Keyword.get(opts, :name, @table_name)

    # Start a GenServer to own the ETS table
    GenServer.start_link(__MODULE__, table_name, name: :"#{table_name}_server")
  end

  # GenServer callbacks
  @impl GenServer
  def init(table_name) do
    # Create the ETS table owned by this process
    case :ets.info(table_name) do
      :undefined ->
        :ets.new(table_name, [:set, :public, :named_table, read_concurrency: true])

      _ ->
        # Table already exists
        :ok
    end

    # Schedule periodic cleanup
    schedule_cleanup()

    {:ok, %{table_name: table_name}}
  end

  @impl GenServer
  def handle_call(msg, _from, state) do
    # Log unexpected calls
    require Logger
    Logger.warning("ETSCache received unexpected call: #{inspect(msg)}")
    {:reply, :ok, state}
  end

  @impl GenServer
  def handle_cast(msg, state) do
    # Log unexpected casts
    require Logger
    Logger.warning("ETSCache received unexpected cast: #{inspect(msg)}")
    {:noreply, state}
  end

  @impl GenServer
  def handle_info(:cleanup_expired, state) do
    cleanup_expired(state.table_name)
    schedule_cleanup()
    {:noreply, state}
  end

  @impl GenServer
  def handle_info(msg, state) do
    # Log unexpected messages
    require Logger
    Logger.warning("ETSCache received unexpected info: #{inspect(msg)}")
    {:noreply, state}
  end

  @impl true
  def get(key, opts \\ []) do
    table = Keyword.get(opts, :table, @table_name)

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
    ArgumentError -> {:error, :table_not_found}
  end

  @impl true
  def set(key, value, ttl) do
    table = @table_name
    expiry = calculate_expiry(ttl)

    :ets.insert(table, {key, value, expiry})
    {:ok, value}
  rescue
    ArgumentError -> {:error, :table_not_found}
  end

  # Overloaded version that accepts options
  def set(key, value, ttl, opts) do
    table = get_table_name(opts)
    expiry = calculate_expiry(ttl)

    :ets.insert(table, {key, value, expiry})
    {:ok, value}
  rescue
    ArgumentError -> {:error, :table_not_found}
  end

  @impl true
  def put(key, value) do
    # Put with no TTL (never expires)
    set(key, value, :infinity)
  end

  # Overloaded version that accepts options
  def put(key, value, opts) do
    table = get_table_name(opts)
    :ets.insert(table, {key, value, :infinity})
    {:ok, value}
  rescue
    ArgumentError -> {:error, :table_not_found}
  end

  @impl true
  def delete(key) do
    :ets.delete(@table_name, key)
    :ok
  rescue
    ArgumentError -> {:error, :table_not_found}
  end

  # Overloaded version that accepts options
  def delete(key, opts) do
    table = get_table_name(opts)
    :ets.delete(table, key)
    :ok
  rescue
    ArgumentError -> {:error, :table_not_found}
  end

  @impl true
  def clear do
    :ets.delete_all_objects(@table_name)
    :ok
  rescue
    ArgumentError -> {:error, :table_not_found}
  end

  # Overloaded version that accepts options
  def clear(opts) do
    table = get_table_name(opts)
    :ets.delete_all_objects(table)
    :ok
  rescue
    ArgumentError -> {:error, :table_not_found}
  end

  @impl true
  def get_and_update(key, update_fun) do
    case get(key) do
      {:ok, current_value} ->
        handle_ets_update_result(key, update_fun.(current_value), current_value)

      {:error, reason} ->
        {nil, {:error, reason}}
    end
  end

  defp handle_ets_update_result(key, update_result, current_value) do
    case update_result do
      {get_value, new_value} ->
        update_ets_cache_value(key, new_value)
        {get_value, new_value}

      :pop ->
        delete(key)
        {current_value, nil}

      other ->
        raise ArgumentError, "Invalid return value from update function: #{inspect(other)}"
    end
  end

  defp update_ets_cache_value(key, :pop), do: delete(key)
  defp update_ets_cache_value(key, new_value), do: put(key, new_value)

  @impl true
  def get_recent_kills do
    # For testing, return empty list
    []
  end

  @impl true
  def get_kill(kill_id) do
    case get("kill:#{kill_id}") do
      {:ok, kill} -> {:ok, kill}
      _ -> {:ok, %{}}
    end
  end

  @impl true
  def init_batch_logging do
    :ok
  end

  @impl true
  def mget(keys) when is_list(keys) do
    results =
      Enum.map(keys, fn key ->
        case get(key) do
          {:ok, nil} -> {:error, :not_found}
          {:ok, value} -> {:ok, value}
          {:error, reason} -> {:error, reason}
        end
      end)

    {:ok, results}
  end

  # Private helpers

  defp get_table_name(opts) do
    Keyword.get(opts, :table, @table_name)
  end

  defp calculate_expiry(:infinity), do: :infinity

  defp calculate_expiry(ttl) when is_integer(ttl) do
    System.system_time(:second) + ttl
  end

  defp expired?(:infinity), do: false

  defp expired?(expiry) when is_integer(expiry) do
    System.system_time(:second) > expiry
  end

  @doc """
  Cleans up expired entries. Can be called periodically if needed.
  """
  def cleanup_expired(table_name \\ @table_name) do
    now = System.system_time(:second)

    :ets.foldl(
      fn {key, _value, expiry}, acc ->
        if expiry != :infinity and expiry < now do
          :ets.delete(table_name, key)
        end

        acc
      end,
      :ok,
      table_name
    )
  rescue
    ArgumentError -> {:error, :table_not_found}
  end

  # Private helper to schedule the next cleanup
  defp schedule_cleanup do
    # Cleanup every 15 minutes
    Process.send_after(self(), :cleanup_expired, :timer.minutes(15))
  end
end
